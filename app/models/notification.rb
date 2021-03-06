# This model keeps track of new item notifications that have been sent to users.
# An item's DOI is used as its identifier.
class Notification < ApplicationRecord
  NEW_ITEM = 'new_item'.freeze

  validates :kind, :doi, presence: true
  validates_inclusion_of :success, in: [true, false]

  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :new_item_notification, -> { where(kind: NEW_ITEM) }
  scope :to_author, ->(uni) { where(uni: uni) }
  scope :for_record, ->(i) { where(doi: i) }

  # Checks whether or not a notification has been sent.
  #
  # @param [String] doi item's DOI
  # @return [true] if there's record of notification
  # @return [false] if there's no record of notification
  def self.sent_new_item_notification?(doi, uni)
    !successful.new_item_notification.to_author(uni).for_record(doi).blank?
  end

  # Creates record of new_item notification just sent
  def self.record_new_item_notification(doi, email, uni, s, sent_at: Time.current)
    Notification.create!(
      kind: NEW_ITEM, doi: doi, uni: uni, email: email,
      sent_at: sent_at, success: s
    )
  end
end
