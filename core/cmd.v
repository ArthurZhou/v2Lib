module core

import readline
import log

pub fn console(logger log.Log) {
	mut l := logger
	l.debug("Console started")
	for true {
		cmd := readline.read_line("") or { l.error(err.str()) }.replace("\r\n", "").replace("\n", "").split(" ")
		if cmd[0] == "exit" {
			l.warn("Now exiting...")
			exit(0)
		}
	}
}