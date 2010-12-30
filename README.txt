Dining philosophers - Erlang implementation
===========================================

This is a sample solution to the Dining Philosophers problem [1] written in Erlang [2]. I picked this up primarily to familiarize myself with Erlang, and because the nature of the problem sounded like a good fit for the language.

Content:
========

conductor.erl provides an implementation based on the conductor solution. 

Improvement suggestions:
========================

 * As far as language goes, could rewrite leveraging gen_server [3] and gen_fsm [4]. Could also break the conductor and philosophers in their own modules for better readability of what the various processes are.

 * Far as the problem itself, writing a Chandy / Misra solution could be a good next setp. From there one should be able to compare efficiency and scalability of both algorithms, and maybe dable with the distributed programming aspects of Erlang.

Thanks, Acknowledgements and License
====================================

The folks on Freenode IRC's #erlang channel were most helpful, thanks for the help, suggestions and code reviews guys.

Consider this code public domain, do whatever with it.

Contact
=======

ttimo@ttimo.net
http://ttimo.typepad.com/

References
==========

[1] http://en.wikipedia.org/wiki/Dining_philosophers
[2] http://erlang.org/about.html
[3] http://www.erlang.org/doc/design_principles/gen_server_concepts.html
[4] http://www.erlang.org/doc/man/gen_fsm.html
