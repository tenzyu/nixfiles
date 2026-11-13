use crate::{protocol::OwnerId, Output};
use std::fmt;
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Role {
    Capture,
    Production,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Lifecycle {
    Idle,
    Preparing,
    Ready,
    Running,
    Degraded,
    Stopping,
    Failed,
}

#[derive(Clone, Debug)]
enum Authority {
    Local,
    Peer { owner: OwnerId, expires: Instant },
}
impl Authority {
    fn matches(&self, peer: Option<&OwnerId>) -> bool {
        match self {
            Self::Local => peer.is_none(),
            Self::Peer { owner, .. } => peer == Some(owner),
        }
    }
    fn expired(&self, now: Instant) -> bool {
        matches!(self,Self::Peer{expires,..}if now>=*expires)
    }
}

#[derive(Clone, Debug)]
enum Phase {
    Idle,
    Preparing(Authority),
    Ready(Authority),
    Running {
        authority: Authority,
        output: Output,
    },
    Degraded {
        authority: Authority,
        output: Option<Output>,
    },
    Stopping {
        authority: Authority,
        output: Option<Output>,
    },
    Failed(Authority),
}
impl Phase {
    fn state(&self) -> Lifecycle {
        match self {
            Self::Idle => Lifecycle::Idle,
            Self::Preparing(_) => Lifecycle::Preparing,
            Self::Ready(_) => Lifecycle::Ready,
            Self::Running { .. } => Lifecycle::Running,
            Self::Degraded { .. } => Lifecycle::Degraded,
            Self::Stopping { .. } => Lifecycle::Stopping,
            Self::Failed(_) => Lifecycle::Failed,
        }
    }
    fn authority(&self) -> Option<&Authority> {
        match self {
            Self::Idle => None,
            Self::Preparing(a) | Self::Ready(a) | Self::Failed(a) => Some(a),
            Self::Running { authority, .. }
            | Self::Degraded { authority, .. }
            | Self::Stopping { authority, .. } => Some(authority),
        }
    }
    fn authority_mut(&mut self) -> Option<&mut Authority> {
        match self {
            Self::Idle => None,
            Self::Preparing(a) | Self::Ready(a) | Self::Failed(a) => Some(a),
            Self::Running { authority, .. }
            | Self::Degraded { authority, .. }
            | Self::Stopping { authority, .. } => Some(authority),
        }
    }
    fn output(&self) -> Option<Output> {
        match self {
            Self::Running { output, .. } => Some(*output),
            Self::Degraded { output, .. } | Self::Stopping { output, .. } => *output,
            _ => None,
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct TransitionError {
    pub from: Lifecycle,
    pub event: &'static str,
}
impl fmt::Display for TransitionError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "invalid lifecycle transition: {:?} via {}",
            self.from, self.event
        )
    }
}
impl std::error::Error for TransitionError {}

#[derive(Debug)]
pub struct Session {
    role: Role,
    phase: Phase,
}
impl Session {
    pub fn new(role: Role) -> Self {
        Self {
            role,
            phase: Phase::Idle,
        }
    }
    pub fn role(&self) -> Role {
        self.role
    }
    pub fn state(&self) -> Lifecycle {
        self.phase.state()
    }
    pub fn output(&self) -> Option<Output> {
        self.phase.output()
    }
    fn error(&self, event: &'static str) -> TransitionError {
        TransitionError {
            from: self.state(),
            event,
        }
    }
    pub fn authorize(&self, owner: Option<&OwnerId>) -> Result<(), TransitionError> {
        if self.phase.authority().is_none_or(|a| a.matches(owner)) {
            Ok(())
        } else {
            Err(self.error("ownership"))
        }
    }
    pub fn lease_expired(&self, now: Instant) -> bool {
        !matches!(self.phase, Phase::Stopping { .. })
            && self.phase.authority().is_some_and(|a| a.expired(now))
    }
    pub fn prepare(
        &mut self,
        owner: Option<OwnerId>,
        now: Instant,
        ttl: Duration,
    ) -> Result<(), TransitionError> {
        if self.state() != Lifecycle::Idle {
            return Err(self.error("prepare"));
        }
        let authority = match owner {
            Some(owner) if self.role == Role::Production => Authority::Peer {
                owner,
                expires: now + ttl,
            },
            Some(_) => return Err(self.error("capture peer ownership")),
            None => Authority::Local,
        };
        self.phase = Phase::Preparing(authority);
        Ok(())
    }
    pub fn prepared(&mut self) -> Result<(), TransitionError> {
        let Phase::Preparing(authority) = &self.phase else {
            return Err(self.error("prepared"));
        };
        self.phase = Phase::Ready(authority.clone());
        Ok(())
    }
    pub fn renew(
        &mut self,
        owner: &OwnerId,
        now: Instant,
        ttl: Duration,
    ) -> Result<(), TransitionError> {
        if !matches!(
            self.state(),
            Lifecycle::Ready | Lifecycle::Running | Lifecycle::Degraded
        ) || self.lease_expired(now)
        {
            return Err(self.error("heartbeat"));
        }
        match self.phase.authority_mut() {
            Some(Authority::Peer {
                owner: held,
                expires,
            }) if held == owner => {
                *expires = now + ttl;
                Ok(())
            }
            _ => Err(self.error("heartbeat owner")),
        }
    }
    pub fn start(&mut self, output: Output) -> Result<(), TransitionError> {
        match &self.phase {
            Phase::Ready(authority) => {
                self.phase = Phase::Running {
                    authority: authority.clone(),
                    output,
                };
                Ok(())
            }
            Phase::Running { output: active, .. } if *active == output => Ok(()),
            _ => Err(self.error("start")),
        }
    }
    pub fn degrade(&mut self) -> Result<(), TransitionError> {
        if !matches!(self.state(), Lifecycle::Ready | Lifecycle::Running) {
            return Err(self.error("degrade"));
        }
        self.phase = Phase::Degraded {
            authority: self.phase.authority().unwrap().clone(),
            output: self.output(),
        };
        Ok(())
    }
    pub fn fail(&mut self) -> Result<(), TransitionError> {
        if !matches!(
            self.state(),
            Lifecycle::Preparing | Lifecycle::Ready | Lifecycle::Running | Lifecycle::Degraded
        ) {
            return Err(self.error("fail"));
        }
        self.phase = Phase::Failed(self.phase.authority().unwrap().clone());
        Ok(())
    }
    pub fn stop(&mut self) -> Result<(), TransitionError> {
        if matches!(self.state(), Lifecycle::Idle | Lifecycle::Stopping) {
            return Ok(());
        }
        self.phase = Phase::Stopping {
            authority: self.phase.authority().unwrap().clone(),
            output: self.output(),
        };
        Ok(())
    }
    pub fn stopped(&mut self) -> Result<(), TransitionError> {
        if self.state() != Lifecycle::Stopping {
            return Err(self.error("stopped"));
        }
        self.phase = Phase::Idle;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn lease_expiry_does_not_retrigger_teardown_while_stopping() {
        let now = Instant::now();
        let mut session = ready(Some(OwnerId::parse("owner").unwrap()), now);
        assert!(session.lease_expired(now + Duration::from_secs(31)));
        session.stop().unwrap();
        assert!(
            !session.lease_expired(now + Duration::from_secs(31)),
            "stopping retriggers automatic expired-lease cleanup"
        );
    }
    fn ready(owner: Option<OwnerId>, now: Instant) -> Session {
        let mut s = Session::new(Role::Production);
        s.prepare(owner, now, Duration::from_secs(30)).unwrap();
        s.prepared().unwrap();
        s
    }
    #[test]
    fn no_output_before_explicit_start_and_no_recording_promotion() {
        let mut s = ready(None, Instant::now());
        assert_eq!(s.output(), None);
        s.start(Output::Recording).unwrap();
        s.start(Output::Recording).unwrap();
        assert!(s.start(Output::Twitch).is_err());
        s.degrade().unwrap();
        assert!(s.start(Output::Twitch).is_err());
        s.fail().unwrap();
        assert_eq!(s.output(), None);
        s.stop().unwrap();
        s.stopped().unwrap();
        assert_eq!(s.state(), Lifecycle::Idle);
    }
    #[test]
    fn ownership_cannot_be_invented_or_revived() {
        let now = Instant::now();
        let owner = OwnerId::parse("owner").unwrap();
        let mut local = ready(None, now);
        assert!(local.renew(&owner, now, Duration::from_secs(30)).is_err());
        let mut peer = ready(Some(owner.clone()), now);
        peer.renew(&owner, now, Duration::from_secs(30)).unwrap();
        assert!(peer
            .renew(
                &owner,
                now + Duration::from_secs(31),
                Duration::from_secs(30)
            )
            .is_err());
        assert!(peer.authorize(None).is_err());
        peer.stop().unwrap();
        peer.stopped().unwrap();
        assert!(!peer.lease_expired(now + Duration::from_secs(90)));
    }
}
