$maintenance_day        = lookup('windows::maintenance::day', { 'default_value' => 'Saturday'})
$maintenance_start_time = lookup('windows::maintenance::start_time', { 'default_value' => '1:30'})
$maintenance_end_time   = lookup('windows::maintenance::end_time', { 'default_value' => '4:30'})

schedule { 'Maintenance Window':
  range   => "${maintenance_start_time} - ${maintenance_end_time}"
  weekday => $maintenance_day,
}

# This just defines a reboot resource, it doesn't reboot the system
reboot { 'before_next_resource':
  when     => pending,
  schedule => 'Maintenance Window',
}

# Do not try and manage these same settings in a GPO as the two will conflict
# Adjust these to match your environment.
class { '::wsus_client' :
  no_auto_update                      => true,
  auto_update_option                  => 'NotifyOnly',
  detection_frequency_hours           => 1,
  no_auto_reboot_with_logged_on_users => false,
  server_url                          => 'http://wsus.example.com',
  # target_group                        => 'ServerUpdates',
  purge_values                        => true,
  before                              => Exec['Install Windows Updates'],
}

# Bootstraps chocolatey
class { '::chocolatey':
  log_output => true,
}

# Makes packages installed via chocolatey show up in Programs and Features
chocolateyfeature { 'autouninstaller':
  ensure   => enabled,
}

# Keep chocolatey updated
package { 'chocolatey':
  ensure   => latest,
  provider => 'chocolatey',
}

# Install the latest version of PowerShell
# This is needed for the execs below to work correctly
package { 'powershell':
  ensure   => latest,
  provider => 'chocolatey',
}

exec { 'Install NuGet package provider':
  command   => '$(Install-PackageProvider -Name NuGet -Force)',
  onlyif    => '$(if((Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue) -eq $null) { exit 0 } else { exit 1 })',
  provider  => 'powershell',
  logoutput => true,
  require   => Package['powershell'],
}

exec { 'Install PSWindowsUpdate module':
  command   => '$(Install-Module -Name PSWindowsUpdate -Scope AllUsers -Force)',
  onlyif    => '$(if((Get-Module PSWindowsUpdate -list) -eq $null) { exit 0 } else { exit 1 })',
  provider  => 'powershell',
  logoutput => true,
  require   => Exec['Install NuGet package provider'],
}

# lint:ignore:140chars
exec { 'Download Windows Updates':
  command   => '$(Get-WUInstall -DownloadOnly -IgnoreUserInput -ShowSearchCriteria -AcceptAll -Verbose)',
  onlyif    => '$(if (@(Get-WUInstall -IgnoreUserInput -ListOnly).Count -gt 0) { exit 0 } else { exit 1 })',
  provider  => 'powershell',
  logoutput => true,
  timeout   => '1200', # Run for up to 20 minutes
  require   => Exec['Install PSWindowsUpdate module'],
}
# lint:endignore

exec { 'Install Windows Updates':
  command   => '$(Get-WUInstall -IgnoreUserInput -ShowSearchCriteria -AcceptAll -IgnoreReboot -Verbose)',
  onlyif    => '$(if (@(Get-WUInstall -IgnoreUserInput -ListOnly).Count -gt 0) { exit 0 } else { exit 1 })',
  provider  => 'powershell',
  logoutput => true,
  timeout   => '1200', # Run for up to 20 minutes
  require   => Exec['Download Windows Updates'],
  schedule  => 'Maintenance Window',
}
