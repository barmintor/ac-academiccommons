require 'rails_helper'

RSpec.describe AcademicCommons::Statistics do
  let(:uni) { 'abc123' }
  let(:pid) { 'actest:1' }

  let(:statistics) do
    class_rig = Class.new
    class_rig.class_eval do
      include AcademicCommons::Statistics
      def repository; end
    end
    class_rig.new
  end

  describe '.collect_asset_pids' do
    let(:original_pids) { ['ac:8', 'ac: 2', "ac:3", "ac:a5", "acc:32"] }
    let(:pid_collection) { original_pids.map {|v| { id: v } } }

    context 'download event' do
      let(:event) { Statistic::DOWNLOAD_EVENT }
      let(:collected_pids) { ['ac:9', 'ac:3', 'ac:4', 'ac:1'] }
      before do
        allow(statistics).to receive(:build_resource_list).with(hash_including(:id))
          .and_return([{pid:'ac:9'}],
                     [{pid:'ac:3'}],
                     [{pid:'ac:4'}],
                     [{pid:'ac:1'}], # method expected to dedupe
                     [{pid:'ac:1'},{pid:'acc:33'}]) # method expected to pick first one
      end

      subject { statistics.send :collect_asset_pids, pid_collection, event }

      it { is_expected.to contain_exactly(*collected_pids) }
    end

    context 'non-download event' do
      let(:event) { Statistic::VIEW_EVENT }
      let(:collected_pids) { original_pids }

      subject { statistics.send :collect_asset_pids, pid_collection, event }
      it { is_expected.to contain_exactly(*collected_pids) }
    end
  end

  describe '.get_author_stats', integration: true do
    before do
      allow(statistics).to receive(:repository).and_return(Blacklight.default_index)
    end
    context 'when requesting usage stats for author' do
      let(:solr_params) do
        {
          :rows => 100000, :sort => 'title_display asc', :q => nil,
          :fq => "author_uni:\"author_uni:#{uni}\"", :fl => "title_display,id,handle,doi,genre_facet",
          :page => 1
        }
      end

      let(:solr_response) do
        {
          'response' => {
            'docs' => [
              { 'id' => pid, 'title_display' => 'First Test Document',
                'handle' => '', 'doi' => '', 'genre_facet' => '' },
            ]
          }
        }
      end

      before :each do
        # Add records for a pid view and download
        FactoryGirl.create(:view_stat)
        FactoryGirl.create(:view_stat)
        FactoryGirl.create(:download_stat)
        FactoryGirl.create(:streaming_stat)

        allow(Blacklight.default_index).to receive(:search)
          .with(solr_params).and_return(solr_response)
      end

      context 'when requesting stats for current month' do
        before :each do
          @results, @stats, @totals, @download_ids = statistics.instance_eval{
            get_author_stats(Date.today - 1.month, Date.today,
              "author_uni:abc123", nil, true, 'author_uni', true, nil)
          }
        end

        it 'returns correct results' do
          expect(@results).to eq solr_response['response']['docs']
        end
        it 'returns correct stats' do
          expect(@stats).to match(
            'View' => { "#{pid}" => 2 },
            'Download' => { "#{pid}" => 1 },
            'Streaming' => { "#{pid}" => 1 },
            'View Lifetime' => { "#{pid}" => 2 },
            'Download Lifetime' => { "#{pid}" => 1 },
            'Streaming Lifetime' => { "#{pid}" => 1 }
          )
        end
        it 'returns correct totals' do
          expect(@totals).to match(
            'View' => 2, 'Download' => 1, 'Streaming' => 1, 'View Lifetime' => 2,
            'Download Lifetime' => 1, 'Streaming Lifetime' => 1
          )
        end
        it 'returns correct download_ids' do
          expect(@download_ids).to include(pid)
          expect(@download_ids[pid]).to contain_exactly('actest:2','actest:4')
        end
      end

      context 'when requesting stats for previous month' do
        before :each do
          @results, @stats, @totals, @download_ids = statistics.instance_eval{
            get_author_stats(Date.today - 2.month, Date.today - 1.month,
              "author_uni:abc123", nil, true, 'author_uni', true, nil)
          }
        end

        it 'returns correct results' do
          expect(@results).to eq solr_response['response']['docs']
        end
        it 'returns empty stats' do
          expect(@stats).to match(
            'View' => {},
            'Download' => { "#{pid}" => 0 },
            'Streaming' => {},
            'View Lifetime' => { "#{pid}" => 2 },
            'Download Lifetime' => { "#{pid}" => 1 },
            'Streaming Lifetime' => { "#{pid}" => 1 }
          )
        end
        it 'returns correct totals' do
          expect(@totals).to match(
            'View' => 0, 'Download' => 0, 'Streaming' => 0, 'View Lifetime' => 2,
            'Download Lifetime' => 1, 'Streaming Lifetime' => 1
          )
        end
      end

      it 'returns correct stats when ommitting streaming views'
    end
  end

  describe '.most_downloaded_asset' do
    let(:pid1) { 'actest:2' }
    let(:pid2) { 'actest:10' }

    subject {
      statistics.instance_eval{ most_downloaded_asset('actest:1') }
    }

    it 'returns error when pid not provided' do
      expect{
        statistics.instance_eval{ most_downloaded_asset }
      }.to raise_error ArgumentError
    end

    context 'when item has one asset' do
      let(:asset_pids_response) do
        [{ pid: pid1 }]
      end

      before :each do
        allow(statistics).to receive(:build_resource_list)
          .with(any_args).and_return(asset_pids_response)
      end

      it 'returns only asset' do
        expect(subject).to eql 'actest:2'
      end
    end

    context 'when item has more than one asset' do
      let(:asset_pids_response) do
        [{ pid: pid1 }, { pid: pid2 }]
      end

      before :each do
        FactoryGirl.create(:download_stat)
        FactoryGirl.create(:download_stat, identifier: pid2)
        FactoryGirl.create(:download_stat, identifier: pid2)
        allow(statistics).to receive(:build_resource_list)
          .with(any_args).and_return(asset_pids_response)
      end

      it 'returns most downloaded' do
        expect(subject).to eql 'actest:10'
      end
    end

    context 'when item asset has never been downloaded' do
      let(:asset_pids_response) do
        [{ pid: pid1 }]
      end

      before :each do
        allow(statistics).to receive(:build_resource_list)
          .with(any_args).and_return(asset_pids_response)
      end

      it 'returns first pid' do
        expect(subject).to eql pid1
      end
    end
  end

  describe '.make_solr_request'
end