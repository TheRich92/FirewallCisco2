FROM python:3.9-slim

# C'est cette ligne qui installe la commande "ip"
RUN apt-get update && apt-get install -y iproute2 && rm -rf /var/lib/apt/lists/*

RUN pip install pyftpdlib

WORKDIR /srv/ftp
RUN mkdir -p /srv/ftp

EXPOSE 21 21000-21010

CMD ["python3", "-m", "pyftpdlib", "-w", "-u", "user", "-P", "pass", "-r", "21000-21010"]