{config, pkgs, ...}:

###### interface
let
  inherit (pkgs.lib) mkOption mapAttrs getAttr fold
    mergeListOption mergeTypedOption mergeAttrsWithFunc;

  options = {
    services = {
      extraJobs = mkOption {
        default = [];
        example = [
             { name = "test-job";
               job = ''
                 description "nc"
                 start on started network-interfaces
                 respawn
                 env PATH=/var/run/current-system/sw/bin
                 exec sh -c "echo 'hello world' | ${pkgs.netcat}/bin/nc -l -p 9000"
                 '';
             } ];
        # should have some checks to verify the syntax
        merge = pkgs.lib.mergeListOption;
        description = "
          Additional Upstart jobs.
        ";
      };

      tools = {
        upstartJobs = mkOption {
          default = {};
          description = "
            List of functions which can be used to create upstart-jobs.
          ";
        };
      };
    };

    tests = {
      upstartJobs = mkOption {
        internal = true;
        default = {};
        description = "
          Make it easier to build individual Upstart jobs. (e.g.,
          <command>nix-build /etc/nixos/nixos -A
          tests.upstartJobs.xserver</command>).
        ";
      };
    };
  };
in

###### implementation
let
  # should be moved to the corresponding jobs.
  nix = config.environment.nix;
  nixEnvVars = config.nix.envVars;
  kernelPackages = config.boot.kernelPackages;
  nssModulesPath = config.system.nssModules.path;
  modprobe = config.system.sbin.modprobe;
  mount = config.system.sbin.mount;

  makeJob = import ../upstart-jobs/make-job.nix {
    inherit (pkgs) runCommand;
  };

  optional = cond: service: pkgs.lib.optional cond (makeJob service);

  requiredTTYs = config.requiredTTYs;

  jobs = map makeJob
    ([
    
    # Network interfaces.
    (import ../upstart-jobs/network-interfaces.nix {
      inherit modprobe config;
      inherit (pkgs) nettools wirelesstools bash writeText;
    })
      
    # Name service cache daemon.
    (import ../upstart-jobs/nscd.nix {
      inherit (pkgs) glibc;
      inherit nssModulesPath;
    })

    # Handles the maintenance/stalled event (single-user shell).
    (import ../upstart-jobs/maintenance-shell.nix {
      inherit (pkgs) bash;
    })

    # Ctrl-alt-delete action.
    (import ../upstart-jobs/ctrl-alt-delete.nix)

  ])

  # ifplugd daemon for monitoring Ethernet cables.
  ++ optional config.networking.interfaceMonitor.enable
    (import ../upstart-jobs/ifplugd.nix {
      inherit (pkgs) ifplugd writeScript bash;
      inherit config;
    })

  # Handles the reboot/halt events.
  ++ (map
    (event: makeJob (import ../upstart-jobs/halt.nix {
      inherit (pkgs) bash utillinux;
      inherit event;
    }))
    ["reboot" "halt" "system-halt" "power-off"]
  )
    
  # User-defined events.
  ++ (map makeJob (config.services.extraJobs));


  command = import ../upstart-jobs/gather.nix {
    inherit (pkgs) runCommand;
    inherit jobs;
  };

in 

{
  require = [
    options
    (import ./lib/default.nix)
  ];

  environment = {
    etc = [{ # The Upstart events defined above.
      source = command + "/etc/event.d";
      target = "event.d";
    }]
    ++ pkgs.lib.concatLists (map (job: job.extraEtc) jobs);

    extraPackages =
      pkgs.lib.concatLists (map (job: job.extraPath) jobs);
  };

  users = {
    extraUsers =
      pkgs.lib.concatLists (map (job: job.users) jobs);

    extraGroups =
      pkgs.lib.concatLists (map (job: job.groups) jobs);
  };

  services = {
    extraJobs = [
      # For the built-in logd job.
      { jobDrv = pkgs.upstart; }
    ];
  };

  tests = {
    # see test/test-upstart-job.sh
    upstartJobs = { recurseForDerivations = true; } //
      builtins.listToAttrs (map (job:
        { name = if job ? jobName then job.jobName else job.name; value = job; }
      ) jobs);
  };
}
