# frozen_string_literal: true

##
# Task automatically assigned to the Hearing Admin organization and/or a member of that team
# when a disposition has not been set on a hearing that was held more than 48 hours ago.
class ChangeHearingDispositionTask < DispositionTask
  before_validation :set_assignee

  def available_actions(_user)
    [
      Constants.TASK_ACTIONS.PLACE_HOLD.to_h,
      Constants.TASK_ACTIONS.CHANGE_HEARING_DISPOSITION.to_h,
      Constants.TASK_ACTIONS.ASSIGN_TO_HEARING_ADMIN_MEMBER.to_h
    ]
  end

  private

  def set_assignee
    self.assigned_to ||= HearingAdmin.singleton
  end
end
