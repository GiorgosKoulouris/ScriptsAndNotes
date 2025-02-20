#!/bin/bash

yum install cups

# On CUPS server
vi /etc/cups/cupsd.conf
# Removed Listen localhost:631
# And added Listen 0.0.0.0:631
# Verify > Browsing On
# Verify > BrowseLocalProtocols dnssd

# For cups-browsed on client
systemctl start cups-browsed
vi /etc/cups/cups-browsed.conf
# Verify > BrowsePoll <hostname>


# Add printer locally (on CUPS)
lpadmin -p testPrinter -E -v socket://localhost:631/printers/testPrinter -m everywhere
# Add printer locally (on client from CUPS)
lpadmin -p testPrinter -E -v socket://tstucps00:631/printers/testPrinter -m everywhere

# test print
lp -d testPrinter /usr/share/cups/data/testprint

# Remove printer
lpadmin -x testPrinter

