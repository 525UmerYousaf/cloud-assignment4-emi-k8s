# httperf, compiled from source. Debian has no httperf package any more.
# Same image as Assignments 02 and 03. Sends the Milestone 04 workload.
FROM debian:12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ca-certificates autoconf automake libtool build-essential \
 && git clone --depth 1 https://github.com/httperf/httperf.git /src \
 && cd /src \
 && autoreconf -i \
 && ./configure \
 && make \
 && make install \
 && apt-get purge -y git autoconf automake libtool build-essential \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/* /src

# httperf opens one file descriptor per connection.
RUN printf '* soft nofile 65535\n* hard nofile 65535\n' >> /etc/security/limits.conf

ENTRYPOINT ["httperf"]
