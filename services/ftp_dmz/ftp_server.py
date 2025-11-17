from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer

authorizer = DummyAuthorizer()

# USER avec mot de passe
authorizer.add_user("user", "passtest2025", "/srv/ftp", perm="elradfmwMT")

# Désactiver anonymous
# authorizer.add_anonymous("/srv/ftp")  # <- on NE l’active PAS

handler = FTPHandler
handler.authorizer = authorizer

server = FTPServer(("0.0.0.0", 21), handler)
server.serve_forever()

