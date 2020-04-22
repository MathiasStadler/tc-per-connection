# tc-per-connection

## housekeeping

```bash
docker run -it -p 8080:8080 -v "/home/trapapa/playground/tc-per-connection:/home/coder/project" -u "$(id -u):$(id -g)" codercom/code-server:latest
git config --global user.name "Mathias Stadler"
git config --global user.EMAIL "email@mathias-stadler.de"
# https://help.github.com/en/github/using-git/caching-your-github-password-in-git
git config --global credential.helper 'cache --timeout=3600'
```



## source

```txt
https://wiki.archlinux.org/index.php/Advanced_traffic_control
```

## test

```bash
# install
# dnf install -y iperf3
# apt-get install -y iperf3
# pacman -S iperf3

# another server start iperf3
iperf -s


# on test server
# PLEASE AWARE: all iprules are overwriten/delete at this test
# TEST NEVER IN PRODUCTION

# enable tc
sudo ./tc-per-connection-all-high-ports.sh enable
# show tc
sudo./tc-per-connection-all-high-ports.sh show

# start test 
iperf -c <ip_of_another_server>

# start test with paralel stream e.g. 2
iperf -P2 -c <ip_of_another_server>


# disable tc
tc-per-connection-all-high-ports.sh disable

```