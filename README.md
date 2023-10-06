# RustDesk Server PRO
Here we have a small collection of [some scripts](https://rustdesk.com/docs/en/self-host/rustdesk-server-pro/installscript/) for RustDesk Server Pro.

> If you are looking for the open source version please go to [RustDesk Server](https://github.com/rustdesk/rustdesk-server)

# Contributing to this repo

You are very welcome to add your PR to improve the current scripts. Some pointers:

### The lib file

The lib.sh is used to avoid duplicate code. Here we collect everything that occurs more than once in the varoius scripts. That could be both `functions()` and `$variables`.

### Indentation

We always use four (4) spaces, not one (1) tab. Please see below for examples.

### IF arguments and functions

The current style is to use it like this:

```
if something
then
    do something
fi
```
Not like:
```
if something; then
    do something
fi
```

Same applies for functions:

```
examplefuntion() [
    if something
    then
        do something
    fi
}
```

### Variables

Variables are always written in CAPITAL LETTERS.

```
EXAMPLEVARIABLE=true
```
