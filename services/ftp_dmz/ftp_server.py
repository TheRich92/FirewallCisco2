from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer

authorizer = DummyAuthorizer()

# USER: user / passtest2025
authorizer.add_user(
    "user",
    "passtest2025",
    "/srv/ftp",
    perm="elradfmwMT"
)

handler = FTPHandler
handler.authorizer = authorizer

# IMPORTANT : passif sur une plage FIXE alignée avec le firewall
handler.passive_ports = range(21000, 21011)

# Optionnel : logs sur la sortie standard
import logging
logging.basicConfig(level=logging.INFO)
handler.banner = "pyftpdlib FTP ready."

address = ("0.0.0.0", 21)
server = FTPServer(address, handler)

if __name__ == "__main__":
    server.serve_forever()
