# mORMot Source Code

## Folder Content

This folder hosts the source code of the *mORMot* Open Source framework, version 2.

## MPL 1.1/GPL 2.0/LGPL 2.1 three-license

The framework source code is licensed under a disjunctive three-license giving the user the choice of one of the three following sets of free software/open source licensing terms:
- *Mozilla Public License*, version 1.1 or later (MPL);
- *GNU General Public License*, version 2.0 or later (GPL);
- *GNU Lesser General Public License*, version 2.1 or later (LGPL), with *linking exception* of the *FPC modified LGPL*.
This allows the use of our code in as wide a variety of software projects as possible, while still maintaining copy-left on code we wrote.

See LICENSE.md file in the root folder of this repository for more information.

## Sub-Folders

The source code tree is split into the following sub-folders:

- `core` for low-level shared components like text, JSON, compression, crypto, network;
- `lib` for external third-party libraries like zlib or openssl;
- `net` for the client/server communication layer;
- `db` for our SQLite3 kernel, and SQL/NoSQL direct access;
- `orm` for high-level ORM features;
- `soa` for high-level SOA features;
- `app` for hosting REST (micro)services/daemons and applications;
- `ddd` for *Domain-Driven-Design* related code.


## Units Naming

By convention:
- Unit names are lowercased, to allow simple access on POSIX or Windows file systems;
- Unit names are dot-separated, and start with the `mormot.` prefix;
- Unit names follow their location in the `src` sub folder, e.g. `mormot.core.json.pas` is located in the `src/core` folder.


## Include Files

To clean the design and enhance source maintainibility, some units have associated `*.inc` source files:
- To regroup Operating-System specific code - e.g. `mormot.core.os.posix.inc` to include non-Windows OS calls;
- To regroup CPU-specific (asm) code - e.g. `mormot.core.crypto.asmx64.inc` to include `x86_64` assembly.
