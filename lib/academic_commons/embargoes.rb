module AcademicCommons
  module Embargoes
    # Deduces whether or not the document given should be accessible.
    # A document can be read if its object state is active and its embargoed
    # date is nil or greater than or equal to today's date.
    #
    # @param [SolrDocument] document solr document of asset(file)
    # @return [Boolean] whether or not document can be accessible
    def free_to_read?(document)
      return false unless document['object_state_ssi'] == 'A'
      free_to_read_start_date = document[:free_to_read_start_date]
      return true unless free_to_read_start_date
      available_today?(free_to_read_start_date)
    end

    # Calculates whether the date given is still under embargo.
    #
    # @note if date is given is a string, it must be in %Y-%m-%d.
    #
    # @param [Date|String] date
    # @return [Boolean]
    def available_today?(date)
      raise 'Date must be a String or Date object' unless(date.is_a?(String) || date.is_a?(Date))
      date = Date.strptime(date, '%Y-%m-%d') if date.is_a?(String)
      Date.today >= date
    end
  end
end
