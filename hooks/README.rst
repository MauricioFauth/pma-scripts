Web hooks for phpMyAdmin
========================

This directory contains various scripts used for development.

Configuration
+++++++++++++

The scripts accessing GitHub need configuration to be able to authorize against
it.

Please copy file ``config-example.php`` to ``config.php`` and fill the different variables.

All variables that begin with ``SMTP_`` are used by the ``push.php`` script, they are not required if you no not use the ``push.php`` script.


WebHooks
++++++++

Use one of the following url examples and set `Content-Type` to `application/x-www-form-urlencoded`

- `protocol://host/folder/hooks/commits.php`
- `protocol://host/folder/hooks/push.php`
- `protocol://host/folder/hooks/docs.php`
- `protocol://host/folder/hooks/website.php`
- `protocol://host/folder/hooks/create_release.php`
- `protocol://host/folder/hooks/create.php`

Scripts
+++++++

Commits checker
---------------

The ``commits.php`` is GitHub hook to check that all commits in a pull request
are in a good shape:

* all have valid Signed-Off-By line
* the patch does not introduce some of coding style violations
    * tab indentation
    * DOS end of lines
    * trailing whitespace
