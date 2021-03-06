import React from 'react';
import { css } from 'glamor';

import DailyDocketRow from './DailyDocketRow';

const docketRowStyle = css({
  borderBottom: '1px solid #ddd',
  '& > div': {
    display: 'inline-block',
    '& > div': {
      verticalAlign: 'top',
      display: 'inline-block',
      padding: '15px'
    }
  },
  '& > div:nth-child(1)': {
    width: '40%',
    '& > div:nth-child(1)': { width: '15%' },
    '& > div:nth-child(2)': { width: '5%' },
    '& > div:nth-child(3)': { width: '50%' },
    '& > div:nth-child(4)': { width: '25%' }
  },
  '& > div:nth-child(2)': {
    backgroundColor: '#f1f1f1',
    width: '60%',
    '& > div': { width: '50%' }
  },
  '&:not(.judge-view) > div:nth-child(1) > div:nth-child(1)': {
    display: 'none'
  }
});

const rowsMargin = css({
  marginLeft: '-40px',
  marginRight: '-40px',
  marginBottom: '-40px'
});

const Header = ({ user }) => (
  <div {...docketRowStyle}
    {...css({
      '& *': {
        background: 'none !important'
      },
      '& > div > div': { verticalAlign: 'bottom' }
    })} className={user.userRoleHearingPrep ? 'judge-view' : ''}>
    <div>
      <div>{user.userRoleHearingPrep && <strong>Prep</strong>}</div>
      <div></div>
      <div><strong>Appellant/Veteran ID/Representative</strong></div>
      <div><strong>Time/RO(s)</strong></div>
    </div>
    <div><div><strong>Actions</strong></div></div>
  </div>
);

export default class DailyDocketHearingRows extends React.Component {
  render () {
    const { hearings, readOnly, regionalOffice, openDispositionModal, user, saveHearing } = this.props;

    return <div {...rowsMargin}>
      <Header user={user} />
      <div>{hearings.map((hearing, index) => (
        <div {...docketRowStyle} key={`docket-row-${index}`} className={user.userRoleHearingPrep ? 'judge-view' : ''}>
          <DailyDocketRow hearingId={hearing.id}
            index={index}
            readOnly={readOnly}
            user={user}
            saveHearing={saveHearing}
            regionalOffice={regionalOffice}
            openDispositionModal={openDispositionModal} />
        </div>
      ))}</div>
    </div>;
  }
}
