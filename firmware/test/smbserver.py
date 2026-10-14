#!/usr/bin/env python3
# smbserver.py - an SMB server for the test bench: impacket's, with its
# error replies put right
#
# impacket answers some failed requests (those that follow a failed
# open in a compound request, for one) with the body of a successful
# reply instead of an SMB2 ERROR body; libsmb2, like the SMB2 spec,
# expects the 9-byte ERROR body, and drops the connection.  And it has
# no answer to the size query that libsmb2's statvfs makes
# (FileFsFullSizeInformation).  Real servers (Windows, Samba, macOS)
# do both properly.
#
#   smbserver.py SHARENAME folder [port]

import os
import sys

from impacket import smb
from impacket import smb3structs as smb2
from impacket import smbserver
from impacket.nt_errors import STATUS_MORE_PROCESSING_REQUIRED

query_fs = smbserver.queryFsInformation


def query_fs_full_size(path, filename, level=None, *args, **kwargs):
    if level == smb2.SMB2_FILESYSTEM_FULL_SIZE_INFO:
        st = os.statvfs(path)
        data = smb.SMBFileFsFullSizeInformation()
        data["TotalAllocationUnits"] = st.f_blocks
        data["CallerAvailableAllocationUnits"] = st.f_bavail
        data["ActualAvailableAllocationUnits"] = st.f_bfree
        data["SectorsPerAllocationUnit"] = 1
        data["BytesPerSector"] = st.f_frsize
        return data.getData()
    return query_fs(path, filename, level, *args, **kwargs)


smbserver.queryFsInformation = query_fs_full_size


def with_error_body(handler):
    def fixed(connId, smbServer, recvPacket):
        commands, packets, status = handler(connId, smbServer, recvPacket)
        if (packets is None and (status & 0xC0000000) == 0xC0000000
                and status != STATUS_MORE_PROCESSING_REQUIRED):
            commands = [smb2.SMB2Error() for _ in commands]
        return commands, packets, status
    return staticmethod(fixed)


for name, value in list(vars(smbserver.SMB2Commands).items()):
    if name.startswith("smb2") and isinstance(value, staticmethod):
        setattr(smbserver.SMB2Commands, name, with_error_body(value.__func__))

share, folder = sys.argv[1], sys.argv[2]
port = int(sys.argv[3]) if len(sys.argv) > 3 else 4450
server = smbserver.SimpleSMBServer(listenAddress="127.0.0.1", listenPort=port)
server.addShare(share, folder, "")
server.setSMB2Support(True)
server.setSMBChallenge("")
server.start()
