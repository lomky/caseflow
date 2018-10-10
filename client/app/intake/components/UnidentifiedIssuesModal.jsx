import { bindActionCreators } from 'redux';
import { connect } from 'react-redux';
import React from 'react';

import { addUnidentifiedIssue } from '../actions/ama';
import Modal from '../../components/Modal';
import TextField from '../../components/TextField';

class UnidentifiedIssuesModal extends React.Component {
  constructor(props) {
    super(props);

    this.state = {
      description: '',
      notes: ''
    };
  }

  onAddIssue = () => {
    this.props.addUnidentifiedIssue(this.state.description, this.state.notes);
    this.props.closeHandler();
  }

  onDescriptionChange = (value) => {
    this.setState({
      description: value
    });
  }

  onNotesChange = (value) => {
    this.setState({
      notes: value
    });
  }

  render() {
    let {
      intakeData,
      closeHandler
    } = this.props;

    const issueNumber = (intakeData.addedIssues || []).length + 1;

    return <div className="intake-add-issues">
      <Modal
        buttons={[
          { classNames: ['cf-modal-link', 'cf-btn-link', 'close-modal'],
            name: 'Cancel adding this issue',
            onClick: closeHandler
          },
          { classNames: ['usa-button', 'usa-button-secondary', 'add-issue'],
            name: 'Add this issue',
            onClick: this.onAddIssue,
            disabled: !this.state.description
          }
        ]}
        visible
        closeHandler={closeHandler}
        title={`Add issue ${issueNumber}`}
      >
        <h2>
        Describe the issue to mark it as needing further review.
        </h2>
        <TextField
          name="Transcribe the issue as it's written on the form"
          strongLabel
          value={this.state.description}
          onChange={this.onDescriptionChange}
        />
        <TextField
          name="Notes"
          optional
          strongLabel
          value={this.state.notes}
          onChange={this.onNotesChange}
        />
      </Modal>
    </div>;
  }
}

export default connect(
  null,
  (dispatch) => bindActionCreators({
    addUnidentifiedIssue
  }, dispatch)
)(UnidentifiedIssuesModal);
