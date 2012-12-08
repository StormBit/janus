What is this?
-------------

This is a (backward compatible) fork of the Janus IRC Channel Linker created by Daniel de Graaf (danieldg) which later got improved by Samuel J Hoffman (miniCruzer).

What is your goal?
------------------

My goal is to make Janus as customizable from the conf file as possible while fixing common issues people may have with it. This is also my reason to learn and use perl.

What changes did you make?
--------------------------

In short? Most of the annoying messages have been disabled. The Controller bot and it's features have been made more configurable from the conf file. A few features like custom (branded) domain names for the Janus bots, forced network tagging and oper sharing level have been added in. The conf file also have been modified a bit to give a better working example and several notes have been added in to avoid confusion.

Quick start:
------------

Run ./configure to check module dependencies and compile multiplex.

See the example configuration for a description of what is needed there.
After editing the configuration start janus by running ./janus.pl

Note: Look in the /doc directory for more help regarding Janus and it's parts.
