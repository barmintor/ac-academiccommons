#
# Methods added to this helper will be available to all templates in the application.
#

require "#{Blacklight.root}/app/helpers/application_helper.rb"


module ApplicationHelper


  def application_name
    'Academic Commons'
  end

  def relative_root
    Rails.configuration.action_controller[:relative_url_root] || ""
  end

  # RSolr presumes one suggested word, this is a temporary fix
  def get_suggestions(spellcheck)
    words = []
    return words if spellcheck.nil?
    suggestions = spellcheck[:suggestions]
    i_stop = suggestions.index("correctlySpelled")
    0.step(i_stop - 1, 2).each do |i|
      term = suggestions[i]
      term_info = suggestions[i+1]
      origFreq = term_info['origFreq']
  # termInfo['suggestion'] is an array of hashes with 'word' and 'freq' keys
      term_info['suggestion'].each do |suggestion|
        if suggestion['freq'] > origFreq
          words << suggestion['word']
        end
      end
    end
    words
  end
  #
  # facet param helpers ->
  #

  # Standard display of a facet value in a list. Used in both _facets sidebar
  # partial and catalog/facet expanded list. Will output facet value name as
  # a link to add that to your restrictions, with count in parens.
  # first arg item is a facet value item from rsolr-ext.
  # options consist of:
  # :suppress_link => true # do not make it a link, used for an already selected value for instance
  def render_facet_value(facet_solr_field, item, options ={})
    link_to_unless(options[:suppress_link], item.label, add_facet_params_and_redirect(facet_solr_field, item.value), :class=>"facet_select") + "<span class='item_count'> (" + format_num(item.hits) + ")</span>" + render_subfacets(facet_solr_field, item, options)
  end
  
  def facet_list_limit
   10
  end

  # Standard display of a SELECTED facet value, no link, special span
  # with class, and 'remove' button.
  def render_selected_facet_value(facet_solr_field, item)
    
   link_to(item.label+"<span class='item_count'> (" + format_num(item.hits) + ")</span>" , remove_facet_params(facet_solr_field, item.value, params), :class=>"facet_deselect") +

    render_subfacets(facet_solr_field, item)
  end
  def render_subfacets(facet_solr_field, item, options ={})
    render = ''
    if (item.instance_variables.include? "@subfacets")
      render = '<span class="toggle">[+/-]</span><ul>'
      item.subfacets.each do |subfacet|
        if facet_in_params?(facet_solr_field, subfacet.value)
          render += '<li>' + render_selected_facet_value(facet_solr_field, subfacet) + '</li>'
        else
          render += '<li>' + render_facet_value(facet_solr_field, subfacet,options) + '</li>'
        end
      end
      render += '</ul>'
    end
    render
  end
end

# jackson added this helper function from rails 3 to generate html5 search field type (rounded corners)

def search_field_tag(name, value = nil, options = {})
         text_field_tag(name, value, options.stringify_keys.update("type" => "search"))
end


def render_meta_as_links()


end


 
  def page_location
    if params[:controller] == "catalog"
      if params[:action] == "index" and params[:q].to_s.blank? and params[:f].to_s.blank? and (params[:search_field].to_s.blank? or params[:search_field] != Blacklight.config[:advanced][:search_field])
        return "home"
      elsif params[:action] == "index"
        return "search_results"
      elsif params[:action] == "show"
        return "record_view"
      elsif params[:action] == "browse" || params[:action] == "browse_department" || params[:action] == "browse_subject"
        return "browse_view"
      end
    elsif params[:controller] == "advanced"
      return "advanced"
    elsif params[:controller] == "search_history"
      return "search_history"
    else
      return "unknown"
    end
  end
