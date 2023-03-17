import vweb
import os
import markdown
import encoding.utf8
import regex
import json
import log
import time
import net.http
import crypto.sha256
import readline

struct App { // main app context
	vweb.Context
}

struct MDData { // markdown extended data structure
	title string
}

struct Config { // config structure
	host string
	port int
	home string
	storage string
	assets string
	log_to_file bool
	log_level string
	enable_login bool
}
struct AccountData {
	keys []struct {
		name string
		hash string
	}
}

__global ( // global variables(add param -enable-globals when running or building)
	ver = "0.0.2-s20220317" // version
	l log.Log // logger
	root = os.getwd() // root path
	keys AccountData
	accounts []string
)

fn read_config() {
	l.debug("Reading config")
	if !os.exists("$root/config.json") { // if config.json does not exist
		mut cfg_file := os.create("$root/config.json") or {
			l.fatal(err.str())
		}
		cfg_file.write('{\n\t"host": "localhost", \n\t"port": 8080, \n\t"home": "home.md", \n\t"storage": "docs", \n\t"assets": "assets", \n\t"log_to_file": false, \n\t"log_level": "DEBUG", \n\t"enable_login": true\n}'.bytes()) or {
			l.error(err.str())
		}
		cfg_file.close()
		l.warn("New config file generated! Restart is required")
		exit(0)
	}
	cfg := os.read_file("$root/config.json") or {
		l.fatal(err.str())
	}
	cfg_data := json.decode(Config, cfg) or {
		l.fatal(err.str())
	}
	os.setenv("HOST", cfg_data.host, false)
	os.setenv("PORT", cfg_data.port.str(), false)
	os.setenv("HOME", cfg_data.home, true)
	os.setenv("STORAGE", cfg_data.storage, true)
	os.setenv("ASSETS", cfg_data.assets, true)
	if cfg_data.enable_login {
		os.setenv("ENABLE_LOGIN", "true", true)
	} else {
		os.setenv("ENABLE_LOGIN", "false", true)
	}

	if cfg_data.log_to_file { // if log to file is enabled
		if !os.exists("$root/logs") { // if logs folder does not exist
			os.mkdir("$root/logs", os.MkdirParams{mode: 0o777}) or {
				l.fatal(err.str())
			}
		}
		log_name := time.now().str().replace(" ", "=").replace(":", "-") + ".log"
		// log files look like: YYYY-MM-DD=HH-MM-SS.log
		os.create("$root/logs/$log_name") or {
			l.fatal(err.str())
		}
		l.set_full_logpath("$root/logs/$log_name")
		l.log_to_console_too()
		l.warn("Logging to file: $log_name")
	}
	// set log levels: FATAL ERROR WARN INFO DEBUG DISABLED
	l.info("Using log level ${cfg_data.log_level}")
	l.set_level(log.level_from_tag(cfg_data.log_level) or {
		l.warn("Invalid log level: ${cfg_data.log_level}")
		log.Level.info
	})
	l.debug("Config loaded")
}

fn load_keys() {
	l.debug("Loading keys")
	if !os.exists("$root/keys.json") { // if config.json does not exist
		mut key_file := os.create("$root/keys.json") or {
			l.fatal(err.str())
		}
		key_file.write('{\n\t"keys": [\n\t\t\n\t]\n}'.bytes()) or {
			l.error(err.str())
		}
		key_file.close()
		l.warn("New key file generated! Restart is required")
		exit(0)
	}
	keys = json.decode(AccountData, os.read_file("$root/keys.json") or {
		l.fatal(err.str())
	}) or {
		l.fatal("Error loading keys  reason: ${err.str()}")
	}
	for name in keys.keys {
		accounts << name.name
	}
	l.debug("Keys loaded")
}

fn load_template() {
	l.debug("Loading templates")
	template := os.read_file("$root/${os.getenv("ASSETS")}/index.html") or {
		l.fatal(err.str())
	}
	os.setenv("TEMPLATE", template, true)
	login := os.read_file("$root/${os.getenv("ASSETS")}/login.html") or {
		l.fatal(err.str())
	}
	os.setenv("LOGIN", login, true)

	mut menubar := ""
	if os.getenv("ENABLE_LOGIN") == "true" {
		menubar = '<li class="menu"><a class="menu" href="/">Home</a></li><li class="logout"><a class="logout" href="/logout">Logout</a></li>'
	} else {
		menubar = '<li class="menu"><a class="menu" href="/">Home</a></li>'
	}
	os.setenv("MENUBAR", menubar, true)
	l.debug("Templates loaded")
}

fn main() {
	defer {
		println("Program terminated by deferred auto shutdown")
		exit(0)
	}

	println('                     
      ___ __    _ _   
  _ _|_  |  |  |_| |_ 
 | | |  _|  |__| | . |
  \\_/|___|_____|_|___|
 ---------------------
   fast small simple
                     ')
	l.set_level(.debug) // set default logging level
	l.info("Starting v2Lib  version:$ver")
	read_config()
	load_template()
	load_keys()

	mut threads := []thread{}
	threads << spawn console()

	l.info("Starting v2Lib server on http://${os.getenv("HOST")}:${os.getenv("PORT")}/")
	vweb.run_at(&App{}, vweb.RunParams{
		host: os.getenv("HOST")
		port: os.getenv("PORT").int()
		family: .ip
		show_startup_message: false
	}) or {
		l.error(err.str())
	}
}

fn getpath(abs_path string) string {
	return "$root/${os.getenv("STORAGE")}/$abs_path"
}

["/"]
fn (mut app App) index() vweb.Result { // redirect to home page when visiting /
	return app.redirect("/docs/${os.getenv("HOME")}")
}

["/login"; get]
fn (mut app App) login() vweb.Result { // show login page
	if os.getenv("ENABLE_LOGIN") == "true" {
		return app.html(os.getenv("LOGIN").replace("{{ ERR }}", ""))
	} else {
		return app.not_found()
	}
}

["/login"; post]
fn (mut app App) handle_login() vweb.Result { // handle login form
	if os.getenv("ENABLE_LOGIN") == "true" {
		form := app.form.clone()
		account_index := accounts.index(form["name"])
		if account_index >= 0 {
			current_acc := keys.keys[account_index]
			if sha256.hexhash(form["pass"]) == current_acc.hash {
				app.set_cookie(http.Cookie{
					name: "account",
					value: current_acc.name,
					path: "/",
				})
				return app.redirect("/docs/${os.getenv("HOME")}")
			} else {
				return app.html(os.getenv("LOGIN").replace("{{ ERR }}", "Wrong username or password"))
			}
		} else {
			return app.html(os.getenv("LOGIN").replace("{{ ERR }}", "Wrong username or password"))
		}
	} else {
		return app.not_found()
	}
}

["/logout"]
fn (mut app App) handle_logout() vweb.Result { // handle login form
	if os.getenv("ENABLE_LOGIN") == "true" {
		app.set_cookie(http.Cookie{
			name: "account",
			value: "",
			path: "/",
		})
		return app.redirect("/login")
	} else {
		return app.not_found()
	}
}

["/assets/:path"]
fn (mut app App) assets(path string) vweb.Result { // serve assets files
	if os.getenv("ENABLE_LOGIN") == "true" {
		if accounts.index(app.get_cookie("account") or { return app.redirect("/login") }) >= 0 {
			return app.file("$root/${os.getenv("ASSETS")}/$path")
		} else {
			return app.redirect("/login")
		}
	} else {
		return app.file("$root/${os.getenv("ASSETS")}/$path")
	}
}

fn render(mut app App, path string) vweb.Result {
	mut page_title := path
	if os.exists(getpath(path)) {
		if path[utf8.len(path)-3..utf8.len(path)] == ".md" {
			mut data := os.read_file(getpath(path)) or {
				l.error(err.str())
				return app.text("Cannot open file: $path")
			}
			if data.contains("<d2lib>") && data.contains("</d2lib>") {
				re := regex.regex_opt("<d2lib>(.*)</d2lib>") or {
					l.error("Error loading extended data for `$path` reason: ${err.str()}")
					return app.server_error(500)
				}
				start, end := re.match_string(data)
				page_data := json.decode(MDData, data[start+7..end-8]) or {
					l.error("Error decoding extended data for `$path` reason: ${err.str()}")
					return app.server_error(500)
				}
				if page_data.title != "" {
					page_title = page_data.title
				}
				data = data.replace(data[start+7..end-8], "").replace("<d2lib>", "").replace("</d2lib>", "")
			}

			return app.html(os.getenv("TEMPLATE").replace("{{ CONTENT }}", markdown.to_html(data)).replace("{{ TITLE }}", page_title).replace("{{ MENU }}", os.getenv("MENUBAR")))

		} else {
			return app.file(getpath(path))
		}
	} else {
		return app.not_found()
	}
}

["/docs/:path"]
fn (mut app App) docs(path string) vweb.Result { // serve docs
	if os.getenv("ENABLE_LOGIN") == "true" {
		if accounts.index(app.get_cookie("account") or { return app.redirect("/login") }) >= 0 {
			return render(mut app, path)
		} else {
			return app.redirect("/login")
		}
	} else {
		return render(mut app, path)
	}
}

fn console() {
	l.debug("Console started")
	for true {
		cmd := readline.read_line("") or { l.error(err.str()) }.replace("\r\n", "").replace("\n", "").split(" ")
		if cmd[0] == "exit" {
			l.warn("Now exiting...")
			exit(0)
		}
	}
}