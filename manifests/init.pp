# backuppc.pp - basic components for configuring backuppc
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.


define backuppc::setting ($val) {

	$p1='^\s*\$Conf\{'
	# (#...)? for idempotency and not killing comments at end of line
	$p2='\}\s*=\s*(?!'
	$p3=')[^;]*;.*$'

	$r1='\$Conf{'

	replace { "backuppc_set_$name":
		file => "/etc/backuppc/config.pl",
		pattern => "$p1$name$p2$val$p3",
		#pattern => $p,
		replacement => "$r1$name} = $val; # managed by puppet"
	}
}

class rsync { 
	package { rsync: ensure => installed }
}

class backuppc::server {
	include apache
	include ssh::client
	include rsync

	module_dir { backuppc: }

	package { [ backuppc, libfile-rsyncp-perl]:
		ensure => installed,
		require => [ User['backuppc'], Group['backuppc'] ]
	}

	user {
		'backuppc':
			uid => 207,
			comment => 'BackupPC',
			home => '/var/lib/backuppc',
			password => '!',
			gid => 207,
			ensure => 'present',
			shell => '/bin/sh'
	}

	group {
		'backuppc':
			gid => '207',
			ensure => 'present'
	}

	file {
		"/var/lib/backuppc/.ssh":
			ensure => directory, mode => 0700,
			owner => backuppc, group => backuppc;
		# ssh caches the changing ssh host keys here
		# prevent this
		"/var/lib/backuppc/.ssh/known_hosts":
			ensure => absent;
		"/var/lib/backuppc/.ssh/abackup.private":
			ensure => present, mode => 0600,
			owner => backuppc, group => backuppc,
			content => file("/etc/puppet/secrets/abackup.private");
		"/usr/share/backuppc/cgi-bin/index.cgi":
			ensure => present, mode => 4755,
			owner => backuppc, group => backuppc,
			require => Package['backuppc'];
	}

	apache::site {
		backuppc:
			ensure => present,
			content => template("backuppc/vhost.conf"),
	}

	backuppc::setting {
		PingMaxMsec: val => "40";
		FullKeepCnt: val => "3";
		BackupFilesExclude: val => '[ "\/proc", "\/sys", "\/backup", "\/media", "\/mnt", "\/var\/cache\/apt\/archives", "\/var\/lib\/vservers\/.hash" ]';
		# wake up really often to catch intermittently connected hosts, wakeup
		# first thing in the morning to do _nightly without disturbing too much
		WakeupSchedule: val => '[ 4.25, 0..23, 0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 10.5, 11.5, 12.5, 13.5, 14.5, 15.5, 16.5, 17.5, 18.5, 19.5, 20.5, 21.5, 22.5, 23.5 ]'
	}

	File <<| tag == "backuppc" |>>
}

class backuppc::client {

	# backuppc connects via SSH, therefore we need a ssh server
	include ssh::server
	include rsync

	file {
		"/var/local/abackup/":
			ensure => directory, mode => 700,
			owner => abackup, group => nogroup;
		"/var/local/abackup/.ssh":
			ensure => directory, mode => 700,
			owner => abackup, group => nogroup;
		"/var/local/abackup/.ssh/authorized_keys":
			ensure => present, mode => 600,
			owner => abackup, group => nogroup,
			content => file("/etc/puppet/secrets/abackup.pub");
	}

	user { "abackup":
		allowdupe => false,
		ensure => present,
		home => "/var/local/abackup/",
		shell => "/bin/bash",
		gid => nogroup
	}

	line {
		abackup_sudoers:
			file => "/etc/sudoers",
			line => "abackup ALL=(ALL) NOPASSWD: /usr/bin/rsync --server --sender --numeric-ids --perms --owner --group --devices --links --times --block-size=2048 --recursive -D *",
			require => Package[sudo];
		abackup_sudoers_tar:
			file => "/etc/sudoers",
			line => "abackup ALL=(ALL) NOPASSWD: /usr/bin/env LC_ALL=C /bin/tar -c -v -f - -C / --totals *",
			require => Package[sudo];
	}

	# TODO: export hosts file
	@@file { "${module_dir_path}/backuppc/${fqdn}":
		ensure => present,
		content => template("backuppc/ssh_config.erb"),
		tag => 'backuppc'
	}
}

