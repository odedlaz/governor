#!/usr/bin/env python

from BaseHTTPServer import BaseHTTPRequestHandler
from helpers.etcd import Etcd
from helpers.postgresql import Postgresql
import sys, yaml, socket, logging
import logging


def handler(postgresql, etcd):
    class StatusHandler(BaseHTTPRequestHandler, object):
        def __init__(self, *args, **kwargs):
            self.etcd = etcd
            self.postgresql = postgresql
            super(StatusHandler, self).__init__(*args, **kwargs)

        def do_GET(self):
            return self.do_ANY()

        def do_OPTIONS(self):
            return self.do_ANY()

        def log_message(self, format, *args):
            logging.debug("%s -> %s\n",
                          self.client_address[0],
                          format % args)

        def do_ANY(self):
            leader = self.etcd.current_leader()["hostname"]
            if self.postgresql.name == leader:
                self.send_response(200)
            else:
                self.send_response(503)

            self.end_headers()
            self.wfile.write('\r\n')
    return StatusHandler


def run(config):
    etcd = Etcd(config["etcd"])
    postgresql = Postgresql(config["postgresql"])
    try:
        from BaseHTTPServer import HTTPServer
        host, port = config["haproxy_status"]["listen"].split(":")
        server = HTTPServer((host, int(port)), handler(postgresql, etcd))
        logging.info('listening on %s:%s', host, port)
        server.serve_forever()

    except KeyboardInterrupt:
        print('^C received, shutting down server')
        server.socket.close()
