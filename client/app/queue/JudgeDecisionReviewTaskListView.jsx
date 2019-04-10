import React from 'react';
import PropTypes from 'prop-types';
import { connect } from 'react-redux';
import { bindActionCreators } from 'redux';
import { sprintf } from 'sprintf-js';
import { css } from 'glamor';

import TaskTable from './components/TaskTable';
import QueueJudgeAssignOrReviewDropdown from './components/QueueJudgeAssignOrReviewDropdown';
import AppSegment from '@department-of-veterans-affairs/caseflow-frontend-toolkit/components/AppSegment';
import Link from '@department-of-veterans-affairs/caseflow-frontend-toolkit/components/Link';
import Alert from '../components/Alert';

import {
  resetErrorMessages,
  resetSuccessMessages,
  resetSaveState
} from './uiReducer/uiActions';
import { clearCaseSelectSearch } from '../reader/CaseSelect/CaseSelectActions';
import { judgeDecisionReviewTasksSelector } from './selectors';

import { fullWidth } from './constants';
import COPY from '../../COPY.json';
import { setMostRecentlyHeldHearingForAppeals } from './QueueActions';
import ApiUtil from '../util/ApiUtil';

const containerStyles = css({
  position: 'relative'
});

class JudgeDecisionReviewTaskListView extends React.PureComponent {
  componentWillUnmount = () => {
    this.props.resetSaveState();
    this.props.resetSuccessMessages();
    this.props.resetErrorMessages();
  }

  componentDidMount = () => {
    this.props.clearCaseSelectSearch();
    this.props.resetErrorMessages();
    const ids = this.props.tasks.map((task) => task.externalAppealId);

    ApiUtil.get(`/appeals/${ids}/hearings_by_id`).then((response) => {
      const resp = JSON.parse(response.text);

      this.props.setMostRecentlyHeldHearingForAppeals(resp.most_recently_held_hearings_by_id);
    });
  };

  render = () => {
    const {
      userId,
      messages,
      tasks
    } = this.props;
    const reviewableCount = tasks.length;
    let tableContent;

    if (reviewableCount === 0) {
      tableContent = <p {...css({ textAlign: 'center',
        marginTop: '3rem' })}>
        {COPY.NO_CASES_IN_QUEUE_MESSAGE}<b><Link to="/search">{COPY.NO_CASES_IN_QUEUE_LINK_TEXT}</Link></b>.
      </p>;
    } else {
      tableContent = <TaskTable
        includeHearingBadge
        includeTask
        includeDetailsLink
        includeDocumentId
        includeType
        includeDocketNumber
        includeIssueCount
        includeDaysWaiting
        tasks={this.props.tasks}
      />;
    }

    return <AppSegment filledBackground styling={containerStyles}>
      <h1 {...fullWidth}>{sprintf(COPY.JUDGE_CASE_REVIEW_TABLE_TITLE, reviewableCount)}</h1>
      <QueueJudgeAssignOrReviewDropdown userId={userId} />
      {messages.error && <Alert type="error" title={messages.error.title}>
        {messages.error.detail}
      </Alert>}
      {messages.success && <Alert type="success" title={messages.success.title}>
        {messages.success.detail || COPY.JUDGE_QUEUE_TABLE_SUCCESS_MESSAGE_DETAIL}
      </Alert>}
      {tableContent}
    </AppSegment>;
  };
}

JudgeDecisionReviewTaskListView.propTypes = {
  tasks: PropTypes.array.isRequired
};

const mapStateToProps = (state) => {
  const {
    ui: {
      messages
    }
  } = state;

  return {
    tasks: judgeDecisionReviewTasksSelector(state),
    messages
  };
};

const mapDispatchToProps = (dispatch) => (
  bindActionCreators({
    clearCaseSelectSearch,
    resetErrorMessages,
    resetSuccessMessages,
    resetSaveState,
    setMostRecentlyHeldHearingForAppeals
  }, dispatch)
);

export default connect(mapStateToProps, mapDispatchToProps)(JudgeDecisionReviewTaskListView);
