# frozen_string_literal: true

class TasksController < ApplicationController
  include Errors

  before_action :verify_task_access, only: [:create]
  skip_before_action :deny_vso_access, only: [:create, :index, :update, :for_appeal]

  TASK_CLASSES = {
    ChangeHearingDispositionTask: ChangeHearingDispositionTask,
    ColocatedTask: ColocatedTask,
    AttorneyRewriteTask: AttorneyRewriteTask,
    AttorneyTask: AttorneyTask,
    GenericTask: GenericTask,
    QualityReviewTask: QualityReviewTask,
    JudgeAssignTask: JudgeAssignTask,
    JudgeQualityReviewTask: JudgeQualityReviewTask,
    ScheduleHearingTask: ScheduleHearingTask,
    TranslationTask: TranslationTask,
    HearingAdminActionTask: HearingAdminActionTask,
    MailTask: MailTask,
    InformalHearingPresentationTask: InformalHearingPresentationTask
  }.freeze

  def set_application
    RequestStore.store[:application] = "queue"
  end

  # e.g, GET /tasks?user_id=xxx&role=colocated
  #      GET /tasks?user_id=xxx&role=attorney
  #      GET /tasks?user_id=xxx&role=judge
  def index
    tasks = queue_class.new(user: user).tasks
    render json: { tasks: json_tasks(tasks) }
  end

  # To create colocated task
  # e.g, for legacy appeal => POST /tasks,
  # { type: ColocatedTask,
  #   external_id: 123423,
  #   title: "poa_clarification",
  #   instructions: "poa is missing"
  # }
  # for ama appeal = POST /tasks,
  # { type: ColocatedTask,
  #   external_id: "2CE3BEB0-FA7D-4ACA-A8D2-1F7D2BDFB1E7",
  #   title: "something",
  #   parent_id: 2
  #  }
  #
  # To create attorney task
  # e.g, for ama appeal => POST /tasks,
  # { type: AttorneyTask,
  #   external_id: "2CE3BEB0-FA7D-4ACA-A8D2-1F7D2BDFB1E7",
  #   title: "something",
  #   parent_id: 2,
  #   assigned_to_id: 23
  #  }
  def create
    return invalid_type_error unless task_class

    tasks = task_class.create_many_from_params(create_params, current_user)

    tasks_to_return = (queue_class.new(user: current_user).tasks + tasks).uniq

    render json: { tasks: json_tasks(tasks_to_return) }
  rescue ActiveRecord::RecordInvalid => error
    invalid_record_error(error.record)
  end

  # To update attorney task
  # e.g, for ama/legacy appeal => PATCH /tasks/:id,
  # {
  #   assigned_to_id: 23
  # }
  # To update colocated task
  # e.g, for ama/legacy appeal => PATCH /tasks/:id,
  # {
  #   status: :on_hold,
  #   on_hold_duration: "something"
  # }
  def update
    tasks = if task.is_a?(GenericTask) && update_params.status == "on_hold"
              GenericTask.place_on_hold(task, update_params)
            else
              task.update_from_params(update_params, current_user)
            end
    tasks.each { |t| return invalid_record_error(t) unless t.valid? }

    tasks_to_return = (queue_class.new(user: current_user).tasks + tasks).uniq

    render json: { tasks: json_tasks(tasks_to_return) }
  end

  def for_appeal
    no_cache

    tasks = TasksForAppeal.new(appeal: appeal, user: current_user, user_role: user_role).call

    render json: {
      tasks: json_tasks(tasks)[:data]
    }
  end

  def ready_for_hearing_schedule
    ro = HearingDayMapper.validate_regional_office(params[:ro])
    tasks = ScheduleHearingTask.tasks_for_ro(ro)
    AppealRepository.eager_load_legacy_appeals_for_tasks(tasks)
    params = { user: current_user, role: user_role }

    render json: AmaAndLegacyTaskSerializer.new(
      tasks: tasks, params: params, ama_serializer: WorkQueue::RegionalOfficeTaskSerializer
    ).call
  end

  def reschedule
    if !task.is_a?(NoShowHearingTask)
      fail(Caseflow::Error::ActionForbiddenError, message: "Can only reschedule NoShowHearingTasks")
    end

    task.reschedule_hearing

    render json: {
      tasks: json_tasks(task.appeal.tasks.includes(*task_includes))[:data]
    }
  end

  private

  def verify_task_access
    if current_user.vso_employee? && task_class != InformalHearingPresentationTask
      fail Caseflow::Error::ActionForbiddenError, message: "VSOs cannot create that task."
    end
  end

  def queue_class
    (user_role == "attorney") ? AttorneyQueue : GenericQueue
  end

  def user_role
    params[:role].to_s.empty? ? "generic" : params[:role].downcase
  end

  def user
    @user ||= User.find(params[:user_id])
  end
  helper_method :user

  def task_class
    additional_task_classes = Hash[
      *MailTask.subclasses.map { |subclass| [subclass.to_s.to_sym, subclass] }.flatten,
      *HearingAdminActionTask.subclasses.map { |subclass| [subclass.to_s.to_sym, subclass] }.flatten
    ]
    classes = TASK_CLASSES.merge(additional_task_classes)
    classes[create_params.first[:type].try(:to_sym)]
  end

  def appeal
    @appeal ||= Appeal.find_appeal_by_id_or_find_or_create_legacy_appeal_by_vacols_id(params[:appeal_id])
  end

  def invalid_type_error
    render json: {
      "errors": [
        "title": "Invalid Task Type Error",
        "detail": "Task type is invalid, valid types: #{TASK_CLASSES.keys}"
      ]
    }, status: :bad_request
  end

  def task
    @task ||= Task.find(params[:id])
  end

  def create_params
    @create_params ||= [params.require("tasks")].flatten.map do |task|
      task = task.permit(:type, :instructions, :action, :label, :assigned_to_id,
                         :assigned_to_type, :external_id, :parent_id, business_payloads: [:description, values: {}])
        .merge(assigned_by: current_user)
        .merge(appeal: Appeal.find_appeal_by_id_or_find_or_create_legacy_appeal_by_vacols_id(task[:external_id]))

      task.delete(:external_id)
      task = task.merge(assigned_to_type: User.name) if !task[:assigned_to_type]

      # Allow actions to be passed with either the key "action" or "label" while we transition to using "label" in place
      # of "action" so requests coming from browsers that have older versions of the javascript bundle succeed.
      task = task.merge(action: task.delete(:label)) if task[:label]

      task
    end
  end

  def update_params
    params.require("task").permit(
      :status,
      :on_hold_duration,
      :assigned_to_id,
      :instructions,
      reassign: [:assigned_to_id, :assigned_to_type, :instructions],
      business_payloads: [:description, values: {}]
    )
  end

  def json_tasks(tasks)
    tasks = AppealRepository.eager_load_legacy_appeals_for_tasks(tasks)
    params = { user: current_user, role: user_role }

    AmaAndLegacyTaskSerializer.new(
      tasks: tasks, params: params, ama_serializer: WorkQueue::TaskSerializer
    ).call
  end

  def task_includes
    [
      :appeal,
      :assigned_by,
      :assigned_to,
      :parent
    ]
  end
end
