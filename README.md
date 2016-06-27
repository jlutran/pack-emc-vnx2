Shinken pack for EMC VNX2
==============================

Shinken configuration pack for EMC VNX² storage arrays


Pre-requisites :
-----------------

- Perl 5
- EMC Navicli 7.33+

Installation :
-----------------

- Clone this repo

- Install the package :

        shinken install --local /path/to/emc-vnx2

- Create a monitoring user in Unisphere and the credentials in the [emc.cfg file](https://github.com/jlutran/pack-emc-vnx2/blob/master/etc/resource.d/emc.cfg)

- Edit the naviseccli path in the [check_emc_vnx2.pl script](https://github.com/jlutran/pack-emc-vnx2/blob/master/libexec/check_emc_vnx2.pl#L20) if necessary.

- Create a /etc/shinken/hosts/emc-vnx2.cfg file containing at least :

        define host {
            host_name <VNX>             # VNX hostname or SID
            address <X.X.X.X>           # SPA or SPB IP address
            use emc-vnx2
        }

- Reload Shinken :

        # service shinken reload
        Reloading arbiter
        Doing config check
        . ok
        . ok
