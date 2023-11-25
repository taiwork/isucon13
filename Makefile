HOME=/home/isucon
APP_HOME=$(HOME)/webapp
APP_DIRECTORY=$(APP_HOME)/ruby
SYSTEMCTL_APP=isupipe-ruby.service

NGINX_LOG=/var/log/nginx/access.log
MYSQL_LOG=/var/log/mysql/mysql-slow.log

BRANCH=$(shell git rev-parse --abbrev-ref HEAD)
SERVER1=isucon@18.177.103.234
SERVER2=isucon@18.176.121.50
SERVER3=isucon@54.250.164.198

# alp
ALPSORT=sum
ALPM="/api/user/.+/icon,/api/user/.+/theme,/api/user/.+/statistics,/api/livestream/\d+/livecomment,/api/livestream/\d+/ngwords,/api/livestream/\d+/exit,/api/livestream/\d+/enter,/api/livestream/\d+/livecomment/\d+/report,/api/livestream/\d+/reaction,/api/livestream/search?tag=.+
OUTFORMAT=count,method,uri,min,max,sum,avg,p99

NOW:=$(shell date "+%Y-%m-%d-%H:%M:%S")

# ====================================================
# デプロイ
# ====================================================
.PHONY: deploy build build-server1 build-app build-nginx build-mysql
deploy:
	ssh $(SERVER1) 'cd $(APP_HOME) && make build'
	ssh $(SERVER2) 'cd $(APP_HOME) && make build'
	ssh $(SERVER3) 'cd $(APP_HOME) && make build'

build:
	cd $(APP_HOME) && git fetch -p && git checkout $(BRANCH) && git pull origin $(BRANCH) && make build-server

# Set app, mysql and nginx.
build-server: build-app build-nginx build-mysql

build-app:
	cd $(APP_HOME) && \
	sudo systemctl disable --now $(SYSTEMCTL_APP) && \
	sudo systemctl enable --now  $(SYSTEMCTL_APP)

build-nginx:
	cd $(APP_HOME) && \
	sudo cp -r ./etc/nginx/* /etc/nginx/
	sudo systemctl restart nginx.service

build-mysql:
	cd $(APP_HOME) && \
	sudo cp -r ./etc/mysql/* /etc/mysql/
	sudo systemctl restart mysql.service


# ====================================================
# 計測
# ====================================================
.PHONY: measure lotate_log lotate_nginx_log lotate_mysql_log restart bench alp mysql_slow_log push
measure:
	ssh $(SERVER1) 'cd $(APP_HOME) && make alp mysql_slow_log lotate_log push restart'
	ssh $(SERVER2) 'cd $(APP_HOME) && make alp mysql_slow_log lotate_log push restart'
	ssh $(SERVER3) 'cd $(APP_HOME) && make alp mysql_slow_log lotate_log push restart'

# log lotation
# logファイルを変えたあとに、nginx, mysqlを再起動すること
lotate_log: lotate_nginx_log lotate_mysql_log

lotate_nginx_log:
	cd $(HOME) && sudo mv $(NGINX_LOG) $(NGINX_LOG).bak.$(NOW)
lotate_mysql_log:
	cd $(HOME) && sudo mv $(MYSQL_LOG) $(MYSQL_LOG).bak.$(NOW)

restart:
	sudo systemctl restart nginx
	sudo systemctl restart mysql
	sudo systemctl restart isucondition.ruby.service

# bench
# bench:
# 	cd $(HOME)/bench && sudo ./bench -all-addresses 127.0.0.11 -target 127.0.0.11:443 -tls -jia-service-url http://127.0.0.1:4999

alp:
	cd $(APP_HOME) && \
	sudo /home/linuxbrew/.linuxbrew/bin/alp ltsv --file=$(NGINX_LOG) --nosave-pos --pos /tmp/alp.pos --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -q -m $(ALPM) > ./measure/alp/$(NOW).log

# mysql slow log
# -s c はクエリの実行回数でソート
# -s at はクエリの平均実行時間でソート
# -s t はクエリの合計実行時間でソート
# -t 10 は上位10件を表示
mysql_slow_log:
	cd $(APP_HOME) && \
	sudo mysqldumpslow -s t /var/log/mysql/mysql-slow.log > ./measure/mysql/$(NOW).log
	# mysqldumpslow -s c -t 10 /var/log/mysql/mysql-slow.log
	# mysqldumpslow -s at -t 10 /var/log/mysql/mysql-slow.log

push: 
	cd $(APP_HOME) && \
	git add measure/ && git commit -m "log $(NOW)" && git push origin $(BRANCH)
