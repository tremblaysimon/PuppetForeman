#!/usr/bin/env python
#
# gitlab-webhook-r10k
#
# A simple webhook service for running r10k on a puppet server.
#
# This will run the process and listen on port 8000 for POST requests from Gitlab. 
# When it receives a request, it will run r10k on the puppet master server.
#
# Usage :
# ./gitlab-webhook-r10k.py --port [x.x.x.x:]8000
#
# Installation :
#  create directory /var/lib/puppet/gitlab-webhook
#  copy gitlab-webhook-r10k.py and gitlab-webhook to this directory
#  set both files as executable (chmod +x ...)
#  create a symlink for the service :
#   ln -s /var/lib/puppet/gitlab-webhook/gitlab-webhook /etc/init.d/gitlab-webhook
#  start the service :
#   service gitlab-webhook start
#  logs are located at /var/log/puppet/gitlab-webhook-r10k-deployer.log
#
# Since r10k might be using ssh, you need a key pair to clone repository :
#  create a key pair :
#   ssh-keygen -t rsa -C "$your_email"
#  result should be stored in the .ssh directory of the user (ex. /root/.ssh)
#  copy to /home/puppet/.ssh/
#   mkdir -p /home/puppet/.ssh
#   cp /root/.ssh/id_rsa* /home/puppet/.ssh
#  only the puppet user should have access to the files in this directory :
#   chown -R puppet. /home/puppet
#   chmod 600 /home/puppet/.ssh/id_rsa
#   chmod -R 600 /home/puppet/.ssh
#  create a "deploy key" in Gitlab for the project using the public generated (id_rsa.pub).
#
# For help: $ ./gitlab-webhook-r10k.py -h
#

import os
import json
import argparse
import BaseHTTPServer
import shlex
import subprocess
import shutil
import logging
import logging.handlers

command         = '/usr/local/bin/r10k deploy environment -pv'
logger_file     = '/var/log/gitlab-webhook-r10k-deployer.log'
logger_max_size = 25165824         # 24 MB
logger_level    = logging.DEBUG    # DEBUG is quite verbose
logger          = logging.getLogger('gitlab-webhook-r10k-deployer')

logger.setLevel(logger_level)
logging_handler = logging.handlers.RotatingFileHandler(logger_file, maxBytes=logger_max_size, backupCount=4)
logging_handler.setFormatter(logging.Formatter("%(asctime)s %(filename)s %(levelname)s %(message)s", "%B %d %H:%M:%S"))
logger.addHandler(logging_handler)

class RequestHandler(BaseHTTPServer.BaseHTTPRequestHandler):
    def do_POST(self):
        logger.info("Received POST request.")
        self.rfile._sock.settimeout(5)
        
        if not self.headers.has_key('Content-Length'):
            return self.error_response()
        
        json_data = self.rfile.read(int(self.headers['Content-Length'])).decode('utf-8')

        try:
            data = json.loads(json_data)
        except ValueError:
            logger.error("Unable to load JSON data '%s'" % json_data)
            return self.error_response()

        logger.info("Running command: %s" % command)
        stream = os.popen(command)

        self.ok_response()
        logger.info("Finished processing POST request.")
        
    def ok_response(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()

    def error_response(self):
        self.log_error("Bad Request.")
        self.send_response(400)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
       
def get_arguments():
    parser = argparse.ArgumentParser(description=('Run r10k on Gitlab webhook request.'))
    parser.add_argument('-p', '--port', default=8000, metavar='8000', help='server address (host:port). host is optional.')
    return parser.parse_args()

def main():
    global command
    
    args = get_arguments()
    address = str(args.port)
    
    if address.find(':') == -1:
        host = '0.0.0.0'
        port = int(address)
    else:
        host, port = address.split(":", 1)
        port = int(port)
    server = BaseHTTPServer.HTTPServer((host, port), RequestHandler)

    logger.info("Starting gitlab-webhook-r10k-deployer at %s:%s." % (host, port))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    logger.info("Stopping gitlab-webhook-r10k-deployer Server.")
    server.server_close()
    
if __name__ == '__main__':
    main()
