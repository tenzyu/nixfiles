use crate::OwnedProcess;
use std::collections::BTreeMap;
use std::io;
use std::time::Duration;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Worker {
    Game,
    Microphone,
    Camera,
    Speech,
    Rnnoise,
    Obs,
    AudioServer,
    Receiver,
    Tunnel,
}
impl Worker {
    pub fn name(self) -> &'static str {
        match self {
            Self::Game => "game",
            Self::Microphone => "mic",
            Self::Camera => "camera",
            Self::Speech => "tts",
            Self::Rnnoise => "rnnoise",
            Self::Obs => "obs",
            Self::AudioServer => "pulse",
            Self::Receiver => "mediamtx",
            Self::Tunnel => "ssh",
        }
    }
}
#[derive(Default)]
pub struct Workers(BTreeMap<Worker, OwnedProcess>);
impl Workers {
    pub fn names(&self) -> Vec<&'static str> {
        self.0.keys().map(|worker| worker.name()).collect()
    }
    pub fn contains(&self, worker: Worker) -> bool {
        self.0.contains_key(&worker)
    }
    pub fn spawn(&mut self, worker: Worker, argv: &[String]) -> io::Result<()> {
        if self.contains(worker) {
            return Err(io::Error::other("worker already owned"));
        }
        self.0.insert(worker, OwnedProcess::spawn(argv)?);
        Ok(())
    }
    pub fn any_exited(&mut self) -> bool {
        self.0
            .values_mut()
            .any(|child| !matches!(child.try_wait(), Ok(None)))
    }
    pub fn stop(&mut self, worker: Worker, grace: Duration) -> io::Result<()> {
        if let Some(child) = self.0.get_mut(&worker) {
            child.stop(grace)?;
            self.0.remove(&worker);
        }
        Ok(())
    }
    pub fn stop_all(&mut self, grace: Duration) -> io::Result<()> {
        let mut failures = Vec::new();
        for worker in self.0.keys().copied().collect::<Vec<_>>() {
            if self.stop(worker, grace).is_err() {
                failures.push(worker.name());
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(io::Error::other(format!(
                "owned workers still require cleanup: {}",
                failures.join(", ")
            )))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_owned_worker_is_included_in_stop() {
        let mut workers = Workers::default();
        for worker in [Worker::Speech, Worker::AudioServer, Worker::Tunnel] {
            workers
                .spawn(worker, &["sleep".into(), "30".into()])
                .unwrap();
        }
        workers.stop_all(Duration::from_millis(10)).unwrap();
        assert!(workers.names().is_empty());
        workers.stop_all(Duration::ZERO).unwrap();
    }
}
