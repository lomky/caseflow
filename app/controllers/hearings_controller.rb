class HearingsController < ApplicationController
  before_action :verify_access, :check_hearing_prep_out_of_service

  def update
    hearing.update(update_params)
    render json: hearing.to_hash
  end

  def logo_name
    "Hearing Prep"
  end

  def logo_path
    hearings_dockets_path
  end

  private

  def check_hearing_prep_out_of_service
    render "out_of_service", layout: "application" if Rails.cache.read("hearing_prep_out_of_service")
  end

  def hearing
    @hearing ||= Hearing.find(hearing_id)
  end

  def hearing_id
    params[:id]
  end

  def verify_access
    verify_authorized_roles("Hearing Prep")
  end

  def set_application
    RequestStore.store[:application] = "hearings"
  end

  def update_params
    params.require("hearing").permit(:notes,
                                     :disposition,
                                     :hold_open,
                                     :aod,
                                     :transcript_requested,
                                     :add_on)
  end
end
