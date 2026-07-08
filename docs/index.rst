tccx
====

.. include:: badges.rst

Reverse-engineering of macOS **TCC** (Transparency, Consent & Control) and **SIP** (System
Integrity Protection), worked out from the ``tccd`` binary shipped at
``TCC.framework/Support/tccd`` (macOS **10.15.6**) and the Ghidra project ``tcc`` - plus
``tcc-preapprove``, a small Swift CLI that implements the findings.

The question the project set out to answer: **can TCC privacy permissions be pre-approved
programmatically?** The short answer, established by reading the binary, is that a genuine
grant can be *constructed* freely, but it can only be *persisted* with SIP's filesystem
protection disabled, or handed to the Apple-sanctioned MDM/PPPC channel.

.. toctree::
   :caption: TCC
   :maxdepth: 2

   tcc-internals

.. toctree::
   :caption: SIP
   :maxdepth: 2

   sip-overview
   sip-configuration
   sip-filesystem-protection
   sip-runtime-protection
   sip-apple-silicon-ssv
   sip-and-tcc

.. toctree::
   :caption: Tool
   :maxdepth: 2

   tcc-preapprove

Building
--------

Everything runs through ``package.json`` scripts:

.. code-block:: shell

   yarn build          # swift build (debug)
   yarn build:release  # swift build -c release
   yarn test           # swift test
   yarn gen-docs       # build these docs (Sphinx)
   swift run tcc-preapprove --help

.. only:: html

   Indices and tables
   ------------------

   * :ref:`genindex`
   * :ref:`search`
