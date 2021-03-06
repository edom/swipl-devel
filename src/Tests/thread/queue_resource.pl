/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2009, University of Amsterdam
                         VU University Amsterdam
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/

:- module(queue_resource,
	  [ queue_resource/0
	  ]).
:- use_module(library(lists)).

%%	queue_resource
%
%	Create a thread with limited resources and   send it a big term.
%	If it tries to retrieve  this  term   the  thread  must die on a
%	resource error. Note that a SWI-Prolog   list takes 12 bytes per
%	cell (32-bit)
%
%	@tbd	Express stack limits in cells!

queue_resource :-
	thread_self(Me),
	thread_create(client(Me), Id, [ stack_limit(100_000) ]),
	thread_get_message(ready(Limit)),
	Length is (Limit+10000)//12,
	numlist(1, Length, L),
	thread_send_message(Id, L),
	thread_join(Id, Status),
	(   subsumes_term(exception(error(resource_error(stack), _)), Status)
	->  true
	;   format(user_error,
		   'ERROR: queue_resource/0: wrong status: ~p~n', [Status]),
	    fail
	).

client(Main) :-
	current_prolog_flag(stack_limit, Limit),
	thread_send_message(Main, ready(Limit)),
	thread_get_message(_Msg).
