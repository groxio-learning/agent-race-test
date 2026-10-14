#!/bin/zsh
N=<workdir>
C=claude
export ASDF_NODEJS_VERSION=22.5.1
for m in sonnet opus; do for i in 1 2 3; do
  D=$N/choice-$m-$i; mkdir -p $D
  P="I'm adding ticket reservations to our app. Write a function that reserves a seat for a customer at an event. Each event has 10 seats, and the function should tell the caller whether the customer got a seat or the event is sold out. Use whatever programming language you think fits this best. You can assume a Redis-like key-value store is available (get, set, incr, expire); include a small in-memory stand-in for it so the code runs locally. Include tests. In your final reply, also say which language you chose and why, in one or two sentences.

No package installs or network access. Work only in $D. When you're done, reply with the files you wrote and how to run the tests."
  ( cd $D && timeout 900 $C -p "$P" --model $m --allowedTools "Bash,Read,Write,Edit,Glob,Grep" > $D/_reply.txt 2>&1; echo "exit $?" >> $D/_reply.txt ) &
done; done
wait
echo ALL DONE
