require 'rails_helper'

describe 'GET /api/v1/record/doi/:doi', type: :request do
  context 'when doi correct' do
    before { get '/api/v1/record/doi/10.7916/ALICE' }
    it 'should return 200' do
      expect(response.status).to be 200
    end

    it 'should return response body with correct record information' do
      expect(JSON.load(response.body)).to match({
        'abstract' => 'Background -  Alice is feeling bored and drowsy while sitting on the riverbank with her older sister, who is reading a book with no pictures or conversations.',
        'author' => ['Carroll, Lewis', 'Weird Old Guys.'],
        'columbia_series' => [],
        'created_at' => '2017-09-14T16:31:33Z',
        'date' => '1865',
        'degree_discipline' => nil,
        'degree_grantor' => nil,
        'degree_level' => nil,
        'degree_name' => nil,
        'department' => ['Bucolic Literary Society.'],
        'embargo_end' => nil,
        'id' => '10.7916/ALICE',
        'language' => ['English'],
        'legacy_id' => 'actest:1',
        'modified_at' => '2017-09-14T16:48:05Z',
        'notes' => nil,
        'persistent_url' => 'https://doi.org/10.7916/ALICE',
        'subject' => ['Tea Parties', 'Wonderland', 'Rabbits', 'Nonsense literature', 'Bildungsromans'],
        'thesis_advisor' => [],
        'title' => 'Alice\'s Adventures in Wonderland',
        'type' => ['Articles'],
        })
      end
  end

  context 'when doi incorrect' do
    before { get '/api/v1/record/doi/10.48472/KDF84' }

    it 'should return 404' do
      expect(response.status).to be 404
    end
  end
end
