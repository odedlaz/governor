import sys, time, re, urllib2, json, psycopg2
import logging
from base64 import b64decode

from governor.helpers import errors

import inspect

logger = logging.getLogger(__name__)


def lineno():
    """Returns the current line number in our program."""
    return inspect.currentframe().f_back.f_lineno

class Ha:
    def __init__(self, state_handler, etcd):
        self.state_handler = state_handler
        self.etcd = etcd

    def acquire_lock(self):
        return self.etcd.attempt_to_acquire_leader(self.state_handler.name)

    def update_lock(self):
        return self.etcd.update_leader(self.state_handler)

    def update_last_leader_operation(self):
        return self.etcd.update_last_leader_operation(self.state_handler.last_operation)

    def is_unlocked(self):
        return self.etcd.leader_unlocked()

    def has_lock(self):
        return self.etcd.am_i_leader(self.state_handler.name)

    def fetch_current_leader(self):
        return self.etcd.current_leader()

    def handle_healthy_node(self):
        if self.acquire_lock():
            if not self.state_handler.is_leader():
                logging.info("promoting self to leader by acquiring session lock")
                self.state_handler.promote()
            logging.info("acquired session lock as a leader")
            return

        if self.state_handler.is_leader():
            logging.info("demoting self due after trying and failing to obtain lock")
            self.state_handler.demote(self.fetch_current_leader())
            return

        logging.info("following new leader after trying and failing to obtain lock")
        self.state_handler.follow_the_leader(self.fetch_current_leader())

    def handle_non_healthy_node(self):
        if self.state_handler.is_leader():
            logging.info("demoting self because i am not the healthiest node")
            self.state_handler.demote(self.fetch_current_leader())
            return

        if self.fetch_current_leader() is None:
            logging.info("waiting on leader to be elected because i am not the healthiest node")
            self.state_handler.follow_no_leader()
            return

        logging.info("following a different leader because i am not the healthiest node")
        self.state_handler.follow_the_leader(self.fetch_current_leader())

    def handle_no_leader(self):
        logging.info("Leader is unlocked - starting election")
        if self.state_handler.is_healthiest_node(self.etcd):
            self.handle_healthy_node()
        else:
            self.handle_non_healthy_node()

    def handle_leader_exists(self):
        if self.has_lock():
            self.handle_lock_owned()
        else:
            self.handle_no_lock()
            
    def handle_lock_owned(self):
        self.update_lock()
        if not self.state_handler.is_leader():
            logging.info("promoting self to leader because i had the session lock")
            self.state_handler.promote()
        logging.info("i am the leader with the lock")

    def handle_no_lock(self):
        logger.info("does not have lock")
        if self.state_handler.is_leader():
            logging.info("demoting self because i do not have the lock and i was a leader")
            self.state_handler.demote(self.fetch_current_leader())
            return

        logging.info("no action. i am a secondary and i am following a leader")
        self.state_handler.follow_the_leader(self.fetch_current_leader())

    def run_cycle(self):
        if not self.state_handler.is_healthy():
            if not self.state_handler.is_running():
                logging.info("postgresql was stopped. starting again.")
                self.state_handler.start()
            logging.info("no action. not healthy enough to do anything.")
        try:
            if self.is_unlocked():
                self.handle_no_leader()
            else:
                self.handle_leader_exists()

        except errors.CurrentLeaderError:
            logger.error("failed to fetch current leader from etcd")
        except psycopg2.OperationalError:
            logger.error("Error communicating with Postgresql.  Will try again.")
        except errors.HealthiestMemberError:
            logger.error("failed to determine healthiest member fromt etcd")

    def run(self):
        while True:
            self.run_cycle()
            time.sleep(10)
