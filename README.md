# kubara kind demo – hub and two spokes

Welcome to the kubara demo for ContainerDays Hamburg 2026. You can find detailed instructions for recreating the demo in the [deep dive](Deep-Dive.md).

## Bootstrap a local development platform with kubara and kind

<img src="z-demo-setup/images/kubara-local-setup-overview-0.png" alt="kubara adds spokes to Argo CD" style="width: 75%; height: auto; border-radius: 16px;">


Bootstrap the local development platform with just a few commands.

```sh
kubara init --prep --local
# Edit .env.
kubara init --local --renovate=false
kubara bootstrap hub --local
```

## Connect to the spokes

Manage the clusters with the kubara CLI using commands such as:

```sh
kubara cluster list
kubara cluster add
```

This creates a list entry in `config.yaml` and adds values to the Argo CD hub
configuration.

Generate the overlay configuration for the spokes and apply it to the hub.

```sh
kubara generate --helm
```

<img src="z-demo-setup/images/kubara-local-setup-4.png" alt="kubara adds spokes to Argo CD" style="width: 75%; height: auto; border-radius: 16px;">



## Who is Johnny?

<img src="z-demo-setup/images/can-you-beat-johnny.png" alt="beat-johnny" style="width: 50%; height: auto; border-radius: 50px;">

*The challenge starts with the [bootstrap sequence](https://docs.kubara.io/latest-stable/3_infrastructure/kind/#bootstrap-sequence).*
