# Create config.bu

```yml
variant: fcos
version: 1.7.0
passwd:
  users:
    - name: <username>
      groups:
        - wheel
        - sudo
      ssh_authorized_keys:
        - <ssh>
    - name: core
      ssh_authorized_keys: []
```

# Compile ignition file

```sh
podman run --interactive --rm quay.io/coreos/butane:release < config.bu > config.ign
```

# Download latest bare-metal CoreOS

```sh
podman run --security-opt label=disable --pull=always --rm -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release download -s stable -p metal -f iso
```

# Embed the ignition file into the ISO

```sh
podman run --privileged --rm -v $PWD:/data -w /data quay.io/coreos/coreos-installer:release iso ignition embed -i config.ign fedora-coreos-44.YOUR.VERSION-live.x86_64.iso
```

# Burn the ISO

```sh
sudo dd if=fedora-coreos-44.YOUR.VERSION-live.x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

# Installing
- ssh into the installation media.
- Copy the ignition contend into a new `config.ign` file.

## Wipe the partition table

```sh
sudo wipefs -a /dev/sdX
```

## Install

```sh
sudo coreos-installer install /dev/sdX -i config.ign
```
