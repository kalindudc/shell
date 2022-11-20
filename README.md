# shell
> source $REPO/src/base.sh

Shared and common aliases and functions for all machines.

### Install (Mac OS)

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

### Directory Structure
```js
.
├── LICENSE
├── README.md
└── src
    ├── aliases.sh
    ├── base.sh             // source this in profile, includes aliasses and functions
    ├── bin/                // quick scripts to run
    │   ├── conf/           // any configuration and properties file required by the scripts
    │   └── ...
    └── functions.sh
```

### Shells pre-requisites
* #### ZSH
  * [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh)

### License
MIT
