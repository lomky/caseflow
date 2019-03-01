# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

DEVELOPMENT_JUDGE_TEAMS = {
  "BVAAABSHIRE" => { attorneys: %w[BVAEERDMAN BVARDUBUQUE BVALSHIELDS] },
  "BVAGSPORER" => { attorneys: %w[BVAOTRANTOW BVAGBOTSFORD BVAJWEHNER1] },
  "BVAEBECKER" => { attorneys: %w[BVAKBLOCK BVACMERTZ BVAHLUETTGEN] },
  "BVARERDMAN" => { attorneys: %w[BVASRITCHIE BVAJSCHIMMEL BVAKROHAN1] },
  "BVAOSCHOWALT" => { attorneys: %w[BVASCASPER1 BVAOWEHNER BVASFUNK1] }
}.freeze

require "database_cleaner"
# rubocop:disable Metrics/ClassLength
# rubocop:disable Metrics/MethodLength
# rubocop:disable Metrics/AbcSize
class SeedDB
  def initialize
    @legacy_appeals = []
    @tasks = []
    @users = []
    @ama_appeals = []
  end

  def create_legacy_appeals(number)
    legacy_appeals = Array.new(number) do |i|
      Generators::LegacyAppeal.create(
        vacols_id: "vacols_id#{i}",
        vbms_id: "vbms_id#{i}",
        vacols_record: {
          status: "Remand"
        }
      )
    end

    @legacy_appeals.push(*legacy_appeals)
    @legacy_appeals.push(LegacyAppeal.create(vacols_id: "reader_id1", vbms_id: "reader_id1"))
  end

  def create_users
    User.create(css_id: "BVASCASPER1", station_id: 101, full_name: "Attorney with cases")
    User.create(css_id: "BVASRITCHIE", station_id: 101, full_name: "Attorney no cases")
    User.create(css_id: "BVAAABSHIRE", station_id: 101, full_name: "Judge with hearings and cases")
    User.create(css_id: "BVARERDMAN", station_id: 101, full_name: "Judge has attorneys with cases")
    User.create(css_id: "BVAEBECKER", station_id: 101, full_name: "Judge has case to assign")
    User.create(css_id: "BVAKKEELING", station_id: 101, full_name: "Judge has case to assign no team")
    User.create(css_id: "BVATWARNER", station_id: 101, full_name: "Build Hearing Schedule")
    User.create(css_id: "BVAGWHITE", station_id: 101, full_name: "BVA Dispatch user with cases")

    Functions.grant!("System Admin", users: User.all.pluck(:css_id))

    create_colocated_users
    create_transcription_team
    create_vso_users_and_tasks
    create_field_vso_and_users
    create_org_queue_users
    create_qr_user
    create_aod_user
    create_privacy_user
    create_lit_support_user
    create_mail_team_user
    create_bva_dispatch_user_with_tasks
    create_case_search_only_user
    create_judge_teams
    create_hearings_team
  end

  def create_judge_teams
    DEVELOPMENT_JUDGE_TEAMS.each_pair do |judge_css_id, h|
      judge = User.find_or_create_by(css_id: judge_css_id, station_id: 101)
      judge_team = JudgeTeam.for_judge(judge) || JudgeTeam.create_for_judge(judge)
      h[:attorneys].each do |css_id|
        OrganizationsUser.add_user_to_organization(User.find_or_create_by(css_id: css_id, station_id: 101), judge_team)
      end
    end
  end

  def create_transcription_team
    transcription_member = User.find_or_create_by(css_id: "TRANSCRIPTION_USER", station_id: 101)
    OrganizationsUser.add_user_to_organization(transcription_member, TranscriptionTeam.singleton)
  end

  def create_hearings_team
    hearings_member = User.find_or_create_by(css_id: "BVATWARNER", station_id: 101)
    OrganizationsUser.add_user_to_organization(hearings_member, HearingsManagement.singleton)
  end

  def create_colocated_users
    secondary_user = FactoryBot.create(:user, full_name: "Secondary VLJ support staff", roles: %w[Reader])
    FactoryBot.create(:staff, :colocated_role, user: secondary_user, sdept: "DSP")
    OrganizationsUser.add_user_to_organization(secondary_user, Colocated.singleton)

    user = User.create(css_id: "BVALSPORER", station_id: 101, full_name: "Co-located with cases", roles: %w[Reader])
    FactoryBot.create(:staff, :colocated_role, user: user, sdept: "DSP")
    OrganizationsUser.add_user_to_organization(user, Colocated.singleton)

    admin = User.create(css_id: "VLJ_SUPPORT_ADMIN", station_id: 101, full_name: "VLJ Support admin", roles: %w[Reader])
    FactoryBot.create(:staff, :colocated_role, user: admin, sdept: "DSP")
    OrganizationsUser.make_user_admin(admin, Colocated.singleton)
  end

  def create_vso_users_and_tasks
    vso = Vso.create(
      name: "VSO",
      url: "veterans-service-organization",
      participant_id: "2452415"
    )

    %w[BILLIE MICHAEL WINNIE].each do |name|
      u = User.create(
        css_id: "#{name}_VSO",
        station_id: 101,
        full_name: "#{name} - VSO user",
        roles: %w[VSO]
      )
      OrganizationsUser.add_user_to_organization(u, vso)

      # Assign one IHP task to each member of the VSO team and leave some IHP tasks assigned to the organization.
      [true, false].each do |assign_to_user|
        a = FactoryBot.create(:appeal)
        root_task = FactoryBot.create(:root_task, appeal: a)
        ihp_task = FactoryBot.create(
          :informal_hearing_presentation_task,
          parent: root_task,
          appeal: a,
          assigned_to: vso
        )
        FactoryBot.create(
          :track_veteran_task,
          parent: root_task,
          appeal: a,
          assigned_to: vso
        )

        next unless assign_to_user

        InformalHearingPresentationTask.create_many_from_params([{
                                                                  parent_id: ihp_task.id,
                                                                  assigned_to_id: u.id,
                                                                  assigned_to_type: User.name
                                                                }], u)
      end
    end
  end

  def create_field_vso_and_users
    vso = FactoryBot.create(:field_vso, name: "Field VSO", url: "field-vso")

    %w[MANDY NICHOLAS ELIJAH].each do |name|
      u = User.create(
        css_id: "#{name}_VSO",
        station_id: 101,
        full_name: "#{name} - VSO user",
        roles: %w[VSO]
      )
      OrganizationsUser.add_user_to_organization(u, vso)

      a = FactoryBot.create(:appeal)
      root_task = FactoryBot.create(:root_task, appeal: a)
      FactoryBot.create(
        :track_veteran_task,
        parent: root_task,
        appeal: a,
        assigned_to: vso
      )
    end
  end

  def create_org_queue_users
    nca = BusinessLine.create!(name: "National Cemetery Administration", url: "nca")
    (0..5).each do |n|
      u = User.create!(station_id: 101, css_id: "NCA_QUEUE_USER_#{n}", full_name: "NCA team member #{n}")
      OrganizationsUser.add_user_to_organization(u, nca)
    end

    (0..5).each do |n|
      u = User.create!(station_id: 101, css_id: "ORG_QUEUE_USER_#{n}", full_name: "Translation team member #{n}")
      OrganizationsUser.add_user_to_organization(u, Translation.singleton)
    end
  end

  def create_qr_user
    qr_user = User.create!(station_id: 101, css_id: "QR_USER", full_name: "QR User")
    OrganizationsUser.add_user_to_organization(qr_user, QualityReview.singleton)

    # Create QR tasks; one assigned just to the QR org and three assigned both to the org and a QR user.
    create_task_at_quality_review
    create_task_at_quality_review(qr_user, "Jane Michael", "Joan Ly")
    create_task_at_quality_review(qr_user, "Cosette Zepeda", "Lian Arroyo")
    create_task_at_quality_review(qr_user, "Huilen Concepcion", "Ilva Urrutia")
  end

  def create_aod_user
    u = User.create!(station_id: 101, css_id: "AOD_USER", full_name: "AOD team member")
    OrganizationsUser.add_user_to_organization(u, AodTeam.singleton)
  end

  def create_privacy_user
    u = User.create!(station_id: 101, css_id: "PRIVACY_TEAM_USER", full_name: "Privacy and FOIA team member")
    OrganizationsUser.add_user_to_organization(u, PrivacyTeam.singleton)
  end

  def create_lit_support_user
    u = User.create!(station_id: 101, css_id: "LIT_SUPPORT_USER", full_name: "Litigation Support team member")
    OrganizationsUser.add_user_to_organization(u, LitigationSupport.singleton)
  end

  def create_mail_team_user
    u = User.create!(station_id: 101, css_id: "JOLLY_POSTMAN", full_name: "Mail team member")
    OrganizationsUser.add_user_to_organization(u, MailTeam.singleton)
  end

  def create_bva_dispatch_user_with_tasks
    u = User.find_by(css_id: "BVAGWHITE")
    OrganizationsUser.add_user_to_organization(u, BvaDispatch.singleton)

    3.times do
      root = FactoryBot.create(:root_task)
      FactoryBot.create_list(
        :request_issue,
        [3, 4, 5].sample,
        :nonrating,
        notes: "Pain disorder with 100\% evaluation per examination",
        decision_review: root.appeal
      )
      parent = FactoryBot.create(
        :bva_dispatch_task,
        assigned_to: BvaDispatch.singleton,
        parent_id: root.id,
        appeal: root.appeal
      )
      FactoryBot.create(
        :bva_dispatch_task,
        assigned_to: u,
        parent_id: parent.id,
        appeal: parent.appeal
      )
    end
  end

  def create_case_search_only_user
    u = User.create!(station_id: 101, css_id: "CASE_SEARCHER_ONLY", full_name: "Case search access. No Queue access")
    FeatureToggle.enable!(:case_search_home_page, users: [u.css_id])
  end

  def create_dispatch_tasks(number)
    num_appeals = @legacy_appeals.length
    tasks = Array.new(number) do |i|
      establish_claim = EstablishClaim.create(
        appeal: @legacy_appeals[i % num_appeals],
        aasm_state: :unassigned,
        prepared_at: rand(3).days.ago
      )
      establish_claim
    end

    # creating user quotas for the existing team quotas
    team_quota = EstablishClaim.todays_quota
    UserQuota.create(team_quota: team_quota, user: @users[3])
    UserQuota.create(team_quota: team_quota, user: @users[4])
    UserQuota.create(team_quota: team_quota, user: @users[5])

    # Give each user a task in a different state
    tasks[0].assign!(@users[0])

    tasks[1].assign!(@users[1])
    tasks[1].start!

    tasks[2].assign!(@users[2])
    tasks[2].start!
    tasks[2].review!
    tasks[2].complete!(status: :routed_to_arc)

    # assigning and moving the task to complete for
    # user at index 3
    5.times do |_index|
      task = EstablishClaim.assign_next_to!(@users[3])
      task.start!
      task.review!
      task.complete!(status: :routed_to_arc)
    end

    task = EstablishClaim.assign_next_to!(@users[4])

    # assigning and moving the task to complete for
    # user at index 5
    3.times do |_index|
      task = EstablishClaim.assign_next_to!(@users[5])
      task.start!
      task.review!
      task.complete!(status: :routed_to_arc)
    end

    task = EstablishClaim.assign_next_to!(@users[6])

    # Create one task with no decision documents
    EstablishClaim.create(
      appeal: tasks[2].appeal,
      created_at: 5.days.ago
    )

    @tasks.push(*tasks)
  end

  def create_default_users
    @users.push(
      User.create(
        css_id: "Reader",
        station_id: "405",
        full_name: "VBMS Station ID maps to multiple VACOLS IDs"
      )
    )
    @users.push(User.create(css_id: "Invalid Role", station_id: "283", full_name: "Cave Johnson"))
    @users.push(User.create(css_id: "Establish Claim", station_id: "283", full_name: "Jane Smith"))
    @users.push(User.create(css_id: "Establish Claim", station_id: "405", full_name: "Carole Johnson"))
    @users.push(User.create(css_id: "Manage Claim Establishment", station_id: "283", full_name: "John Doe"))
    @users.push(User.create(css_id: "Certify Appeal", station_id: "283", full_name: "John Smith"))
    @users.push(User.create(css_id: "System Admin", station_id: "283", full_name: "Angelina Smith"))
    @users.push(User.create(css_id: "Reader", station_id: "283", full_name: "Angelina Smith"))
    @users.push(User.create(css_id: "Hearing Prep", station_id: "283", full_name: "Lauren Roth"))
    @users.push(User.create(css_id: "Mail Intake", station_id: "283", full_name: "Kwame Nkrumah"))
    @users.push(User.create(css_id: "Admin Intake", station_id: "283", full_name: "Ash Ketchum"))
  end

  def create_annotations
    Generators::Annotation.create(comment: "Hello World!", document_id: 1, x: 300, y: 400)
    Generators::Annotation.create(comment: "This is an example comment", document_id: 2)
  end

  def create_ramp_elections(number)
    number.times do |i|
      RampElection.create!(
        veteran_file_number: "#{i + 1}5555555",
        notice_date: 1.week.ago
      )
    end

    %w[11555555 12555555].each do |i|
      RampElection.create!(
        veteran_file_number: i,
        notice_date: 3.weeks.ago
      )
    end
  end

  def create_tags
    DocumentsTag.create(
      tag_id: Generators::Tag.create(text: "Service Connected").id,
      document_id: 1
    )
    DocumentsTag.create(
      tag_id: Generators::Tag.create(text: "Right Knee").id,
      document_id: 2
    )
  end

  def create_hearings
    Generators::Hearing.create
  end

  def create_ama_hearing(day)
    vet = Generators::Veteran.build(
      file_number: Faker::Number.number(9).to_s,
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name
    )
    vet.save

    app = FactoryBot.create(
      :appeal,
      veteran_file_number: vet.file_number,
      docket_type: "hearing"
    )

    Hearing.create(
      hearing_day: day,
      appeal: app,
      bva_poc: User.find_by_css_id("BVAAABSHIRE").full_name,
      scheduled_time: Time.utc(
        Time.zone.today.year, Time.zone.today.month, Time.zone.today.day, 9, 0, 0
      )
    )
  end

  def create_legacy_hearing(day, ro_key)
    case ro_key
    when "RO17"
      folder_nr = "3620725"
    when "RO45"
      folder_nr = "3411278"
    when "C"
      folder_nr = "3542942"
    end

    FactoryBot.create(
      :case_hearing,
      folder_nr: folder_nr,
      vdkey: day.id,
      board_member: User.find_by_css_id("BVAAABSHIRE").vacols_attorney_id.to_i
    )
  end

  def create_hearing_days
    %w[C RO17 RO45].each do |ro_key|
      user = User.find_by(css_id: "BVATWARNER")

      (1..5).each do |index|
        day = HearingDay.create!(
          regional_office: (ro_key == "C") ? nil : ro_key,
          room: "1",
          judge: User.find_by_css_id("BVAAABSHIRE"),
          request_type: (ro_key == "C") ? "C" : "V",
          scheduled_for: Time.zone.today + (index * 11).days,
          created_by: user,
          updated_by: user
        )

        case index
        when 1
          create_ama_hearing(day)
        when 2
          create_legacy_hearing(day, ro_key)
        when 3
          create_legacy_hearing(day, ro_key)
          create_ama_hearing(day)
        end
      end
    end
  end

  def create_legacy_case_with_open_schedule_hearing_task(ro_key)
    case ro_key
    when "RO17"
      vacols_id = "2668454"
    when "RO45"
      vacols_id = "3261587"
    when "C"
      vacols_id = "3019752"
    end

    appeal = LegacyAppeal.find_or_create_by_vacols_id(vacols_id)

    ScheduleHearingTask.create!(
      appeal: appeal,
      assigned_to: HearingsManagement.singleton,
      parent: RootTask.find_or_create_by!(appeal: appeal)
    )
  end

  def create_ama_case_with_open_schedule_hearing_task(ro_key)
    vet = Generators::Veteran.build(
      file_number: Faker::Number.number(9).to_s,
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name
    )

    vet.save

    appeal = FactoryBot.create(
      :appeal,
      :with_tasks,
      number_of_claimants: 1,
      closest_regional_office: ro_key,
      veteran_file_number: vet.file_number,
      docket_type: "hearing"
    )

    ScheduleHearingTask.create!(
      appeal: appeal,
      assigned_to: HearingsManagement.singleton,
      parent: RootTask.find_or_create_by!(appeal: appeal)
    )
  end

  def create_veterans_ready_for_hearing
    %w[C RO45 RO17].each do |ro_key|
      create_legacy_case_with_open_schedule_hearing_task(ro_key)
      create_ama_case_with_open_schedule_hearing_task(ro_key)
    end
  end

  def create_api_key
    ApiKey.new(consumer_name: "PUBLIC", key_string: "PUBLICDEMO123").save!
  end

  def create_higher_level_review_tasks
    6.times do
      veteran = FactoryBot.create(:veteran)
      epe = FactoryBot.create(:end_product_establishment, veteran_file_number: veteran.file_number)
      higher_level_review = FactoryBot.create(
        :higher_level_review,
        end_product_establishments: [epe],
        veteran_file_number: veteran.file_number
      )
      3.times do
        FactoryBot.create(:request_issue,
                          :nonrating,
                          end_product_establishment: epe,
                          veteran_participant_id: veteran.participant_id,
                          decision_review: higher_level_review)
      end
      FactoryBot.create(:higher_level_review_task,
                        assigned_to: Organization.find_by(name: "National Cemetery Administration"),
                        appeal: higher_level_review)
    end
  end

  def create_ama_appeals
    notes = "Pain disorder with 100\% evaluation per examination"

    @appeal_with_vso = FactoryBot.create(
      :appeal,
      claimants: [
        FactoryBot.build(:claimant, participant_id: "CLAIMANT_WITH_PVA_AS_VSO"),
        FactoryBot.build(:claimant, participant_id: "OTHER_CLAIMANT")
      ],
      veteran_file_number: "701305078",
      docket_type: "direct_review",
      request_issues: FactoryBot.create_list(:request_issue, 3, :nonrating, notes: notes)
    )

    es = "evidence_submission"
    dr = "direct_review"
    [
      { number_of_claimants: nil, veteran_file_number: "783740847", docket_type: es, request_issue_count: 3 },
      { number_of_claimants: nil, veteran_file_number: "963360019", docket_type: dr, request_issue_count: 2 },
      { number_of_claimants: 1, veteran_file_number: "604969679", docket_type: dr, request_issue_count: 1 },
      { number_of_claimants: 1, veteran_file_number: "228081153", docket_type: es, request_issue_count: 1 },
      { number_of_claimants: 1, veteran_file_number: "152003980", docket_type: dr, request_issue_count: 3 },
      { number_of_claimants: 1, veteran_file_number: "375273128", docket_type: dr, request_issue_count: 1 },
      { number_of_claimants: 1, veteran_file_number: "682007349", docket_type: dr, request_issue_count: 5 },
      { number_of_claimants: 1, veteran_file_number: "231439628", docket_type: dr, request_issue_count: 1 },
      { number_of_claimants: 1, veteran_file_number: "975191063", docket_type: dr, request_issue_count: 8 },
      { number_of_claimants: 1, veteran_file_number: "662643660", docket_type: dr, request_issue_count: 8 },
      { number_of_claimants: 1, veteran_file_number: "162726229", docket_type: dr, request_issue_count: 8 },
      { number_of_claimants: 1, veteran_file_number: "760362568", docket_type: dr, request_issue_count: 8 }
    ].each do |params|
      @ama_appeals << FactoryBot.create(
        :appeal,
        number_of_claimants: params[:number_of_claimants],
        veteran_file_number: params[:veteran_file_number],
        docket_type: params[:docket_type],
        request_issues: FactoryBot.create_list(
          :request_issue, params[:request_issue_count], :nonrating, notes: notes
        )
      )
    end

    LegacyAppeal.create(vacols_id: "2096907", vbms_id: "228081153S")
    LegacyAppeal.create(vacols_id: "2226048", vbms_id: "213912991S")
    LegacyAppeal.create(vacols_id: "2249056", vbms_id: "608428712S")
    LegacyAppeal.create(vacols_id: "2306397", vbms_id: "779309925S")
    LegacyAppeal.create(vacols_id: "2657227", vbms_id: "169397130S")
  end

  def create_higher_level_reviews_and_supplemental_claims
    veteran_file_number = "682007349"
    veteran = Veteran.find_by(file_number: veteran_file_number)

    ep_rating_code = "030HLRR"
    ep_nonrating_code = "030HLRNR"

    one_day_in_seconds = 60 * 60 * 24
    two_days_in_seconds = 2 * one_day_in_seconds
    thirty_days_in_seconds = 30 * one_day_in_seconds

    higher_level_review = HigherLevelReview.create!(
      veteran_file_number: veteran_file_number,
      receipt_date: Time.zone.now - thirty_days_in_seconds,
      informal_conference: false,
      same_office: false,
      benefit_type: "compensation"
    )
    higher_level_review.create_claimants!(
      participant_id: "5382910292",
      payee_code: "10"
    )

    EndProductEstablishment.create!(
      source: higher_level_review,
      veteran_file_number: veteran.file_number,
      claim_date: Time.zone.now - thirty_days_in_seconds,
      code: ep_rating_code,
      station: "397",
      benefit_type_code: "1",
      payee_code: "00",
      synced_status: "CAN",
      claimant_participant_id: veteran.participant_id
    )

    EndProductEstablishment.create!(
      source: higher_level_review,
      veteran_file_number: veteran.file_number,
      claim_date: Time.zone.now - thirty_days_in_seconds,
      code: ep_rating_code,
      station: "397",
      benefit_type_code: "1",
      payee_code: "00",
      synced_status: nil,
      claimant_participant_id: veteran.participant_id
    )

    EndProductEstablishment.create!(
      source: higher_level_review,
      veteran_file_number: veteran.file_number,
      claim_date: Time.zone.now - thirty_days_in_seconds,
      code: ep_rating_code,
      station: "397",
      benefit_type_code: "1",
      payee_code: "00",
      synced_status: "PEND",
      claimant_participant_id: veteran.participant_id
    )

    EndProductEstablishment.create!(
      source: higher_level_review,
      veteran_file_number: veteran.file_number,
      claim_date: Time.zone.now - thirty_days_in_seconds,
      code: ep_rating_code,
      station: "397",
      benefit_type_code: "1",
      payee_code: "00",
      synced_status: "CLR",
      last_synced_at: Time.zone.now - one_day_in_seconds,
      claimant_participant_id: veteran.participant_id
    )

    EndProductEstablishment.create!(
      source: higher_level_review,
      veteran_file_number: veteran.file_number,
      claim_date: Time.zone.now - thirty_days_in_seconds,
      code: ep_nonrating_code,
      station: "397",
      benefit_type_code: "1",
      payee_code: "00",
      synced_status: "CLR",
      last_synced_at: Time.zone.now - two_days_in_seconds,
      claimant_participant_id: veteran.participant_id
    )

    EndProductEstablishment.create!(
      source: higher_level_review,
      veteran_file_number: veteran.file_number,
      claim_date: Time.zone.now - thirty_days_in_seconds,
      code: ep_rating_code,
      station: "397",
      benefit_type_code: "1",
      payee_code: "00",
      synced_status: "LOL",
      claimant_participant_id: veteran.participant_id
    )

    eligible_request_issue = RequestIssue.create!(
      decision_review: higher_level_review,
      issue_category: "Military Retired Pay",
      nonrating_issue_description: "nonrating description",
      contention_reference_id: "1234",
      ineligible_reason: nil,
      benefit_type: "compensation",
      decision_date: Date.new(2018, 5, 1)
    )

    untimely_request_issue = RequestIssue.create!(
      decision_review: higher_level_review,
      issue_category: "Active Duty Adjustments",
      nonrating_issue_description: "nonrating description",
      contention_reference_id: "12345",
      decision_date: Date.new(2018, 5, 1),
      benefit_type: "compensation",
      ineligible_reason: :untimely
    )

    higher_level_review.create_issues!([
                                         eligible_request_issue,
                                         untimely_request_issue
                                       ])
    higher_level_review.establish!

    SupplementalClaim.create(
      veteran_file_number: veteran.file_number,
      receipt_date: Time.zone.now,
      benefit_type: "compensation"
    )
  end

  def create_root_task(appeal)
    FactoryBot.create(:root_task, appeal: appeal)
  end

  def create_task_at_judge_assignment(appeal, judge, assigned_at = Time.zone.yesterday)
    FactoryBot.create(:ama_judge_task,
                      assigned_to: judge,
                      assigned_at: assigned_at,
                      appeal: appeal,
                      parent: create_root_task(appeal))
  end

  def create_task_at_judge_review(appeal, judge, attorney)
    parent = FactoryBot.create(:ama_judge_task,
                               :in_progress,
                               assigned_to: judge,
                               appeal: appeal,
                               parent: create_root_task(appeal))
    child = FactoryBot.create(
      :ama_attorney_task,
      assigned_to: attorney,
      assigned_by: judge,
      parent: parent,
      appeal: appeal
    )
    child.update(status: :completed)
    FactoryBot.create(:attorney_case_review, task_id: child.id)
  end

  def create_task_at_colocated(appeal, judge, attorney, task_attributes = {})
    parent = FactoryBot.create(
      :ama_judge_task,
      :on_hold,
      assigned_to: judge,
      appeal: appeal,
      parent: create_root_task(appeal)
    )

    atty_task = FactoryBot.create(
      :ama_attorney_task,
      :on_hold,
      assigned_to: attorney,
      assigned_by: judge,
      parent: parent,
      appeal: appeal
    )

    org_task_args = { appeal: appeal,
                      parent: atty_task,
                      assigned_by: attorney,
                      assigned_to: Colocated.singleton }.merge(task_attributes)
    FactoryBot.create(:ama_colocated_task, :on_hold, org_task_args)
  end

  def create_colocated_legacy_tasks(attorney)
    [
      { vacols_id: "2096907", trait: nil, additional: { action: "schedule_hearing" } },
      { vacols_id: "2226048", trait: nil, additional: { action: "translation" } },
      { vacols_id: "2249056", trait: :in_progress },
      { vacols_id: "2306397", trait: :on_hold },
      { vacols_id: "2657227", trait: :completed_hold }
    ].each do |attrs|
      org_task_args = { appeal: LegacyAppeal.find_by(vacols_id: attrs[:vacols_id]),
                        assigned_by: attorney,
                        assigned_to: Colocated.singleton }.merge(attrs[:additional] || {})
      FactoryBot.create(:colocated_task, :on_hold, org_task_args)
    end
  end

  def create_task_at_attorney_review(appeal, judge, attorney)
    parent = FactoryBot.create(
      :ama_judge_task,
      :on_hold,
      assigned_to: judge,
      appeal: appeal,
      parent: create_root_task(appeal)
    )

    FactoryBot.create(
      :ama_attorney_task,
      :in_progress,
      assigned_to: attorney,
      assigned_by: judge,
      parent: parent,
      appeal: appeal
    )
  end

  def create_task_at_quality_review(qr_user = nil, judge_name = nil, attorney_name = nil)
    root_task = FactoryBot.create(:root_task)
    appeal = root_task.appeal

    judge = FactoryBot.create(:user, station_id: 101)
    judge.update!(full_name: judge_name) if judge_name
    FactoryBot.create(:staff, :judge_role, user: judge)
    judge_task = JudgeAssignTask.create!(appeal: appeal, parent: root_task, assigned_to: judge)

    atty = FactoryBot.create(:user, station_id: 101)
    atty.update!(full_name: attorney_name) if attorney_name
    FactoryBot.create(:staff, :attorney_role, user: atty)
    atty_task_params = [{ appeal: appeal, parent_id: judge_task.id, assigned_to: atty, assigned_by: judge }]
    atty_task = AttorneyTask.create_many_from_params(atty_task_params, judge).first

    # Happens in CaseReviewConcern.update_task_and_issue_dispositions()
    atty_task.update!(status: Constants.TASK_STATUSES.completed)
    judge_task.update!(status: Constants.TASK_STATUSES.completed)

    qr_org_task = QualityReviewTask.create_from_root_task(root_task)

    if qr_user
      qr_task_params = [{
        appeal: appeal,
        parent_id: qr_org_task.id,
        assigned_to_id: qr_user.id,
        assigned_to_type: qr_user.class.name,
        assigned_by: qr_user
      }]
      QualityReviewTask.create_many_from_params(qr_task_params, qr_user).first
    end
  end

  def create_tasks
    attorney = User.find_by(css_id: "BVASCASPER1")
    judge = User.find_by(css_id: "BVAAABSHIRE")

    create_task_at_judge_assignment(@ama_appeals[0], judge, 35.days.ago)
    create_task_at_judge_assignment(@ama_appeals[1], judge)
    create_task_at_judge_assignment(@ama_appeals[2], judge)
    create_task_at_judge_assignment(@ama_appeals[3], judge)
    create_task_at_judge_review(@ama_appeals[4], judge, attorney)
    create_task_at_judge_review(@ama_appeals[5], judge, attorney)
    create_task_at_colocated(@ama_appeals[6], judge, attorney)
    create_task_at_colocated(FactoryBot.create(:appeal), judge, attorney, action: "translation")
    create_task_at_attorney_review(@ama_appeals[7], judge, attorney)
    create_task_at_attorney_review(@ama_appeals[8], judge, attorney)
    create_task_at_judge_assignment(@ama_appeals[9], judge)
    create_task_at_judge_review(@ama_appeals[10], judge, attorney)
    create_task_at_colocated(@ama_appeals[11], judge, attorney)

    9.times do
      appeal = FactoryBot.create(:appeal)
      create_task_at_judge_assignment(appeal, judge, Time.zone.today)
    end

    create_colocated_legacy_tasks(attorney)

    FactoryBot.create_list(
      :generic_task,
      5,
      assigned_by: judge,
      assigned_to: Translation.singleton,
      parent: FactoryBot.create(:root_task)
    )
  end

  def create_board_grant_tasks
    nca = BusinessLine.find_by(name: "National Cemetery Administration")
    description = "Service connection for pain disorder is granted with an evaluation of 50\% effective May 1 2011"
    notes = "Pain disorder with 80\% evaluation per examination"

    3.times do |index|
      board_grant_task = FactoryBot.create(:board_grant_effectuation_task,
                                           status: "assigned",
                                           assigned_to: nca)

      request_issues = FactoryBot.create_list(:request_issue, 3,
                                              :nonrating,
                                              contested_issue_description: "#{index} #{description}",
                                              notes: "#{index} #{notes}",
                                              benefit_type: nca.url,
                                              decision_review: board_grant_task.appeal)

      request_issues.each do |request_issue|
        # create matching decision issue
        FactoryBot.create(
          :decision_issue,
          :nonrating,
          disposition: "allowed",
          decision_review: board_grant_task.appeal,
          request_issues: [request_issue],
          promulgation_date: 2.months.ago,
          benefit_type: request_issue.benefit_type
        )
      end
    end
  end

  def create_veteran_record_request_tasks
    nca = BusinessLine.find_by(name: "National Cemetery Administration")

    3.times do |_index|
      FactoryBot.create(:veteran_record_request_task,
                        status: "assigned",
                        assigned_to: nca)
    end
  end

  def clean_db
    DatabaseCleaner.clean_with(:truncation)
    r = Redis.new(url: Rails.application.secrets.redis_url_cache)
    r.keys.each { |k| r.del(k) }
  end

  def setup_dispatch
    CreateEstablishClaimTasksJob.perform_now
    Timecop.freeze(Date.yesterday) do
      # Tasks prepared on today's date will not be picked up
      Dispatch::Task.all.each(&:prepare!)
      # Appeal decisions (decision dates) for partial grants have to be within 3 days
      CSV.foreach(Rails.root.join("local/vacols", "cases.csv"), headers: true) do |row|
        row_hash = row.to_h
        if %w[amc_full_grants remands_ready_for_claims_establishment].include?(row_hash["vbms_key"])
          VACOLS::Case.where(bfkey: row_hash["vacols_id"]).first.update(bfddec: Time.zone.today)
        end
      end
    end
  rescue AASM::InvalidTransition
    Rails.logger.info("Taks prepare job skipped - tasks were already prepared...")
  end

  def create_previously_held_hearing_data
    user = User.find_by_css_id("BVAAABSHIRE")
    appeal = LegacyAppeal.find_or_create_by(vacols_id: "3617215", vbms_id: "994806951S")

    return if ([appeal.type] - ["Post Remand", "Original"]).empty? &&
              appeal.hearings.map(&:disposition).include?(:held)

    FactoryBot.create(:case_hearing, :disposition_held, user: user, folder_nr: appeal.vacols_id)
  end

  def create_legacy_issues_eligible_for_opt_in
    # this vet number exists in local/vacols VBMS and BGS setup csv files.
    veteran_file_number_legacy_opt_in = "872958715S"
    legacy_vacols_id = "LEGACYID"

    # always delete and start fresh
    VACOLS::Case.where(bfkey: legacy_vacols_id).delete_all
    VACOLS::CaseIssue.where(isskey: legacy_vacols_id).delete_all

    case_issues = []
    %w[5240 5241 5242 5243 5250].each do |lev2|
      case_issues << FactoryBot.create(:case_issue,
                                       issprog: "02",
                                       isscode: "15",
                                       isslev1: "04",
                                       isslev2: lev2)
    end
    correspondent = VACOLS::Correspondent.find_or_create_by(stafkey: 100)
    folder = VACOLS::Folder.find_or_create_by(ticknum: legacy_vacols_id, tinum: 1)
    vacols_case = FactoryBot.create(:case_with_soc,
                                    :status_advance,
                                    case_issues: case_issues,
                                    correspondent: correspondent,
                                    folder: folder,
                                    bfkey: legacy_vacols_id,
                                    bfcorlid: veteran_file_number_legacy_opt_in)
    FactoryBot.create(:legacy_appeal, vacols_case: vacols_case)
  end

  def create_ama_hearing_appeals
    description = "Service connection for pain disorder is granted with an evaluation of 70\% effective May 1 2011"
    notes = "Pain disorder with 100\% evaluation per examination"

    FeatureToggle.enable!(:ama_acd_tasks)
    FeatureToggle.enable!(:ama_auto_case_distribution)

    @ama_appeals << FactoryBot.create(
      :appeal,
      :with_tasks,
      number_of_claimants: 1,
      veteran_file_number: "808415990",
      docket_type: "hearing",
      closest_regional_office: "RO17",
      request_issues: FactoryBot.create_list(
        :request_issue, 1, contested_issue_description: description, notes: notes
      )
    )
    @ama_appeals << FactoryBot.create(
      :appeal,
      :with_tasks,
      number_of_claimants: 1,
      veteran_file_number: "992190636",
      docket_type: "hearing",
      closest_regional_office: "RO17",
      request_issues: FactoryBot.create_list(
        :request_issue, 8, contested_issue_description: description, notes: notes
      )
    )

    user = User.find_by(css_id: "BVATWARNER")
    HearingDay.create(
      regional_office: "RO17",
      request_type: "V",
      scheduled_for: 5.days.from_now,
      room: "001",
      created_by: user,
      updated_by: user
    )
  end

  def seed
    clean_db
    # Annotations and tags don't come from VACOLS, so our seeding should
    # create them in all envs
    create_annotations
    create_tags
    create_ama_appeals
    create_users
    create_hearing_days
    create_veterans_ready_for_hearing
    create_tasks
    create_higher_level_review_tasks

    setup_dispatch
    create_previously_held_hearing_data
    create_legacy_issues_eligible_for_opt_in

    create_higher_level_reviews_and_supplemental_claims

    create_ama_hearing_appeals
    create_board_grant_tasks
    create_veteran_record_request_tasks

    FetchHearingLocationsForVeteransJob.perform_now

    return if Rails.env.development?

    # The fake data here is only necessary when we're not running
    # a VACOLS copy locally.
    create_default_users
    create_legacy_appeals(50)
    create_dispatch_tasks(50)
    create_ramp_elections(9)
    create_hearings
    create_api_key
  end
end
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/AbcSize
# rubocop:enable Metrics/ClassLength

SeedDB.new.seed
