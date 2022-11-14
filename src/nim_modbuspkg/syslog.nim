const
  LOG_EMERG* = 0
  LOG_ALERT* = 1
  LOG_CRIT* = 2
  LOG_ERR* = 3
  LOG_WARNING* = 4
  LOG_NOTICE* = 5
  LOG_INFO* = 6
  LOG_DEBUG* = 7
  LOG_KERN* = (0 shl 3)           ##  kernel messages
  LOG_USER* = (1 shl 3)           ##  random user-level messages
  LOG_MAIL* = (2 shl 3)           ##  mail system
  LOG_DAEMON* = (3 shl 3)         ##  system daemons
  LOG_AUTH* = (4 shl 3)           ##  security/authorization messages
  LOG_SYSLOG* = (5 shl 3)         ##  messages generated internally by syslogd
  LOG_LPR* = (6 shl 3)            ##  line printer subsystem
  LOG_NEWS* = (7 shl 3)           ##  network news subsystem
  LOG_UUCP* = (8 shl 3)           ##  UUCP subsystem
  LOG_CRON* = (9 shl 3)           ##  clock daemon
  LOG_AUTHPRIV* = (10 shl 3)      ##  security/authorization messages (private)
  LOG_FTP* = (11 shl 3)           ##  ftp daemon
  LOG_LOCAL0* = (16 shl 3)        ##  reserved for local use
  LOG_LOCAL1* = (17 shl 3)        ##  reserved for local use
  LOG_LOCAL2* = (18 shl 3)        ##  reserved for local use
  LOG_LOCAL3* = (19 shl 3)        ##  reserved for local use
  LOG_LOCAL4* = (20 shl 3)        ##  reserved for local use
  LOG_LOCAL5* = (21 shl 3)        ##  reserved for local use
  LOG_LOCAL6* = (22 shl 3)        ##  reserved for local use
  LOG_LOCAL7* = (23 shl 3)        ##  reserved for local use
  LOG_PID* = 0x00000001
  LOG_CONS* = 0x00000002
  LOG_ODELAY* = 0x00000004
  LOG_NDELAY* = 0x00000008
  LOG_NOWAIT* = 0x00000010
  LOG_PERROR* = 0x00000020

proc c_closelog() {.importc: "closelog", header: "syslog.h".}
proc c_openlog(ident: cstring; option: cint; facility: cint) {.importc: "openlog",
    header: "syslog.h".}
proc c_syslog(pri: cint; fmt: cstring) {.varargs, importc: "syslog",
    header: "syslog.h".}

const
  defaultIdent = ""
  defaultFacility = LOG_USER

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc openlog*(ident: string = defaultIdent, facility: int = defaultFacility) =
  c_openlog(ident.cstring, LOG_PID, facility.cint)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc syslog*(pri: cint, msg: string) =
  c_syslog(pri, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc closelog*() =
  c_closelog()

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc emerg*(msg: string) =
  syslog(LOG_EMERG, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc alert*(msg: string) =
  syslog(LOG_ALERT, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc crit*(msg: string) =
  syslog(LOG_CRIT, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc error*(msg: string) =
  syslog(LOG_ERR, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc info*(msg: string) =
  syslog(LOG_INFO, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc debug*(msg: string) =
  syslog(LOG_DEBUG, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc warn*(msg: string) =
  syslog(LOG_WARNING, msg)

# ------------------------------------------------------------------------------
#
# ------------------------------------------------------------------------------
proc warning*(msg: string) =
  syslog(LOG_WARNING, msg)


when isMainModule:
  openlog("SyslogTest")
  info("log-info")
  error("log-error")
