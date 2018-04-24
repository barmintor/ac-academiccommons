class Admin::AuthorAffiliationReportController < ApplicationController
  before_action :require_admin!

  def index; end

  def create
    csv = AcademicCommons::Metrics::AuthorAffiliationReport.generate_csv(current_user)
    send_data csv, type: 'application/csv', filename: 'author_affiliation_report.csv'
  end
end
