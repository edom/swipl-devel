/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2019, VU University Amsterdam
			 CWI, Amsterdam
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

:- module(xsb,
          [ add_lib_dir/1,			% +Directories
	    add_lib_dir/2,			% +Root, +Directories

            compile/2,                          % +File, +Options
            load_dyn/1,                         % +File
            load_dyn/2,                         % +File, +Direction
            load_dync/1,                        % +File
            load_dync/2,                        % +File, +Direction

            set_global_compiler_options/1,	% +Options
            compiler_options/1,			% +Options

            xsb_import/2,                       % +Preds, From
            xsb_dynamic/1,                      % +Preds

            fail_if/1,				% :Goal

            not_exists/1,			% :Goal
            sk_not/1,				% :Goal

            xsb_findall/3,			% +Template, :Goal, -Answers

            op(1050,  fy, import),
            op(1050,  fx, export),
            op(1040, xfx, from),
            op(1100,  fy, index),               % ignored
            op(1100,  fy, ti),                  % transformational indexing?
            op(1100,  fx, mode),                % ignored
            op(900,   fy, not)                  % defined as op in XSB
          ]).
:- use_module(library(error)).
:- use_module(library(debug)).
:- use_module(library(dialect/xsb/source)).
:- use_module(library(dialect/xsb/tables)).

/** <module> XSB Prolog compatibility layer

This  module  provides  partial  compatibility   with  the  [XSB  Prolog
system](http://xsb.sourceforge.net/)
*/

:- meta_predicate
    xsb_import(:, +),                   % Module interaction
    xsb_dynamic(:),

    compile(:, +),                      % Loading files
    load_dyn(:),
    load_dyn(:, +),
    load_dync(:),
    load_dync(:, +),

    fail_if(0),                         % Meta predicates
    not_exists(0),
    sk_not(0),

    xsb_findall(+,0,-).


		 /*******************************
		 *	    LIBRARY SETUP	*
		 *******************************/

%%	push_xsb_library
%
%	Pushes searching for  dialect/xsb  in   front  of  every library
%	directory that contains such as sub-directory.

push_xsb_library :-
    (   absolute_file_name(library(dialect/xsb), Dir,
			   [ file_type(directory),
			     access(read),
			     solutions(all),
			     file_errors(fail)
			   ]),
	asserta((user:file_search_path(library, Dir) :-
		prolog_load_context(dialect, xsb))),
	fail
    ;   true
    ).

:- push_xsb_library.

%!  setup_dialect
%
%   Further dialect initialization.  Called from expects_dialect/1.

:- public setup_dialect/0.

setup_dialect :-
    style_check(-discontiguous).

:- multifile
    user:term_expansion/2,
    user:goal_expansion/2.

:- dynamic
    moved_directive/2.

% Register XSB specific term-expansion to rename conflicting directives.

user:term_expansion(In, Out) :-
    prolog_load_context(dialect, xsb),
    xsb_term_expansion(In, Out).

xsb_term_expansion((:- Directive), []) :-
    prolog_load_context(file, File),
    retract(moved_directive(File, Directive)),
    debug(xsb(header), 'Moved to head: ~p', [Directive]),
    !.
xsb_term_expansion((:- import Preds from From),
                   (:- xsb_import(Preds, From))).
xsb_term_expansion((:- index(_PI, _How)), []).
xsb_term_expansion((:- index(_PI)), []).
xsb_term_expansion((:- ti(_PI)), []).
xsb_term_expansion((:- mode(_Modes)), []).
xsb_term_expansion((:- dynamic(Preds)), (:- xsb_dynamic(Preds))).

user:goal_expansion(In, Out) :-
    prolog_load_context(dialect, xsb),
    (   xsb_mapped_predicate(In, Out)
    ->  true
    ;   xsb_inlined_goal(In, Out)
    ).

xsb_mapped_predicate(expand_file_name(File, Expanded),
                     xsb_expand_file_name(File, Expanded)).
xsb_mapped_predicate(findall(Template, Goal, List),
                     xsb_findall(Template, Goal, List)).

xsb_inlined_goal(fail_if(P), \+(P)).

%!  xsb_import(:Predicates, +From)
%
%   Make Predicates visible in From. As the XSB library structructure is
%   rather different from SWI-Prolog's, this is a heuristic process.

:- dynamic
    mapped__module/2.                           % XSB name -> Our name

xsb_import(Into:Preds, From) :-
    mapped__module(From, Mapped),
    !,
    xsb_import(Preds, Into, Mapped).
xsb_import(Into:Preds, From) :-
    xsb_import(Preds, Into, From).

xsb_import(Var, _Into, _From) :-
    var(Var),
    !,
    instantiation_error(Var).
xsb_import((A,B), Into, From) :-
    !,
    xsb_import(A, Into, From),
    xsb_import(B, Into, From).
xsb_import(Name/Arity, Into, From) :-
    functor(Head, Name, Arity),
    xsb_mapped_predicate(Head, NewHead),
    functor(NewHead, NewName, Arity),
    !,
    xsb_import(NewName/Arity, Into, From).
xsb_import(PI, Into, usermod) :-
    !,
    export(user:PI),
    @(import(user:PI), Into).
xsb_import(Name/Arity, Into, _From) :-
    functor(Head, Name, Arity),
    predicate_property(Into:Head, iso),
    !,
    debug(xsb(import), '~p: already visible (ISO)', [Into:Name/Arity]).
xsb_import(PI, Into, From) :-
    import_from_module(clean, PI, Into, From),
    !.
xsb_import(PI, Into, From) :-
    prolog_load_context(file, Here),
    absolute_file_name(From, Path,
                       [ extensions(['P', pl, prolog]),
                         access(read),
                         relative_to(Here),
                         file_errors(fail)
                       ]),
    !,
    debug(xsb(import), '~p: importing from ~p', [Into:PI, Path]),
    load_module(Into:Path, PI).
xsb_import(PI, Into, From) :-
    absolute_file_name(library(From), Path,
                       [ extensions(['P', pl, prolog]),
                         access(read),
                         file_errors(fail)
                       ]),
    !,
    debug(xsb(import), '~p: importing from ~p', [Into:PI, Path]),
    load_module(Into:Path, PI).
xsb_import(Name/Arity, Into, _From) :-
    functor(Head, Name, Arity),
    predicate_property(Into:Head, visible),
    !,
    debug(xsb(import), '~p: already visible', [Into:Name/Arity]).
xsb_import(PI, Into, From) :-
    import_from_module(dirty, PI, Into, From),
    !.
xsb_import(_Name/_Arity, _Into, From) :-
    existence_error(xsb_module, From).

%!  import_from_module(?Clean, +PI, +Into, +From) is semidet.
%
%   Try to import PI into  module  Into   from  Module  From.  The clean
%   version only deals  with  cleanly   exported  predicates.  The dirty
%   version is more aggressive.

import_from_module(clean, PI, Into, From) :-
    module_property(From, exports(List)),
    memberchk(PI, List),
    !,
    debug(xsb(import), '~p: importing from module ~p', [Into:PI, From]),
    @(import(From:PI), Into).
import_from_module(dirty, PI, Into, From) :-
    current_predicate(From:PI),
    !,
    debug(xsb(import), '~p: importing from module ~p', [Into:PI, From]),
    (   check_exported(From, PI)
    ->  @(import(From:PI), Into)
    ;   true
    ).
import_from_module(dirty, PI, _Into, From) :-
    module_property(From, file(File)),
    !,
    print_message(error, xsb(not_in_module(File, From, PI))).

check_exported(Module, PI) :-
    module_property(Module, exports(List)),
    memberchk(PI, List),
    !.
check_exported(Module, PI) :-
    module_property(Module, file(File)),
    print_message(error, xsb(not_in_module(File, Module, PI))).

load_module(Into:Path, PI) :-
    use_module(Into:Path, []),
    (   module_property(Module, file(Path))
    ->  file_base_name(Path, File),
        file_name_extension(Base, _, File),
        (   Base == Module
        ->  true
        ;   atom_concat(xsb_, Base, Module)
        ->  map_module(Base, Module)
        ;   print_message(warning,
                          xsb(file_loaded_into_mismatched_module(Path, Module))),
            map_module(Base, Module)
        )
    ;   print_message(warning, xsb(loaded_unknown_module(Path)))
    ),
    import_from_module(_, PI, Into, Module).

map_module(XSB, Module) :-
    mapped__module(XSB, Module),
    !.
map_module(XSB, Module) :-
    assertz(mapped__module(XSB, Module)).


		 /*******************************
		 *      BUILT-IN PREDICATES	*
		 *******************************/

%!  add_lib_dir(+Directories) is det.
%!  add_lib_dir(+Root, +Directories) is det.
%
%   Add    members    of    the    comma      list     Directories    to
%   user:library_directory/1.  If  Root  is  given,    all   members  of
%   Directories are interpreted relative to Root.

add_lib_dir(Directories) :-
    add_lib_dir('.', Directories).

add_lib_dir(_, Var) :-
    var(Var),
    !,
    instantiation_error(Var).
add_lib_dir(Root, (A,B)) :-
    !,
    add_lib_dir(Root, A),
    add_lib_dir(Root, B).
add_lib_dir(Root, a(Dir)) :-
    !,
    add_to_library_directory(Root, Dir, asserta).
add_lib_dir(Root, Dir) :-
    add_to_library_directory(Root, Dir, assertz).

add_to_library_directory(Root, Dir, How) :-
    (   expand_file_name(Dir, [Dir1])
    ->  true
    ;   Dir1 = Dir
    ),
    relative_file_name(TheDir, Root, Dir1),
    exists_directory(TheDir),
    !,
    (   user:library_directory(TheDir)
    ->  true
    ;   call(How, user:library_directory(TheDir))
    ).
add_to_library_directory(_, _, _).

%!  compile(File, Options)
%
%   The XSB version compiles a file into .xwam without loading it. We do
%   not have that. Calling qcompile/1 seems the best start.

compile(File, _Options) :-
    qcompile(File).

%!  load_dyn(+FileName) is det.
%!  load_dyn(+FileName, +Direction) is det.
%!  load_dync(+FileName) is det.
%!  load_dync(+FileName, +Direction) is det.
%
%   Proper implementation requires  the   Quintus  `all_dynamic` option.
%   SWI-Prolog never had that as  clause/2   is  allowed on static code,
%   which is the main reason to want this.
%
%   The _dync_ versions demand source in canonical format. In SWI-Prolog
%   there is little reason to demand this.

load_dyn(File)       :-
    '$style_check'(Style, Style),
    setup_call_cleanup(
        style_check(-singleton),
        load_files(File),
        '$style_check'(_, Style)).
        load_dyn(File, Dir)  :- must_be(oneof([z]), Dir), load_dyn(File).
load_dync(File)      :- load_dyn(File).
load_dync(File, Dir) :- load_dyn(File, Dir).

%!  set_global_compiler_options(+List) is det.
%
%   Set the XSB global compiler options.

:- multifile xsb_compiler_option/1.
:- dynamic   xsb_compiler_option/1.

set_global_compiler_options(List) :-
    must_be(list, List),
    maplist(set_global_compiler_option, List).

set_global_compiler_option(+Option) :-
    !,
    valid_compiler_option(Option),
    (   xsb_compiler_option(Option)
    ->  true
    ;   assertz(xsb_compiler_option(Option))
    ).
set_global_compiler_option(-Option) :-
    !,
    valid_compiler_option(Option),
    retractall(xsb_compiler_option(Option)).
set_global_compiler_option(-Option) :-
    valid_compiler_option(Option),
    (   xsb_compiler_option(Option)
    ->  true
    ;   assertz(xsb_compiler_option(Option))
    ).

valid_compiler_option(Option) :-
    must_be(oneof([ singleton_warnings_off,
                    optimize,
                    allow_redefinition,
                    xpp_on
                  ]), Option).

%!  compiler_options(+Options) is det.
%
%   Locally switch the compiler options

compiler_options(Options) :-
    must_be(list, Options),
    maplist(compiler_option, Options).

compiler_option(+Option) :-
    !,
    valid_compiler_option(Option),
    set_compiler_option(Option).
compiler_option(-Option) :-
    !,
    valid_compiler_option(Option),
    clear_compiler_option(Option).
compiler_option(Option) :-
    valid_compiler_option(Option),
    set_compiler_option(Option).

set_compiler_option(singleton_warnings_off) :-
    style_check(-singleton).
set_compiler_option(optimize) :-
    set_prolog_flag(optimise, true).
set_compiler_option(allow_redefinition).
set_compiler_option(xpp_on).

clear_compiler_option(singleton_warnings_off) :-
    style_check(+singleton).
clear_compiler_option(optimize) :-
    set_prolog_flag(optimise, false).
clear_compiler_option(allow_redefinition).
clear_compiler_option(xpp_on).

%!  xsb_dynamic(Preds)
%
%   Apply dynamic to the original predicate.  This deals with a sequence
%   that seems common in XSB:
%
%       :- import p/1 from x.
%       :- dynamic p/1.

xsb_dynamic(M:Preds) :-
    xsb_dynamic_(Preds, M).

xsb_dynamic_(Preds, _M) :-
    var(Preds),
    !,
    instantiation_error(Preds).
xsb_dynamic_((A,B), M) :-
    !,
    xsb_dynamic_(A, M),
    xsb_dynamic_(B, M).
xsb_dynamic_(Name/Arity, M) :-
    functor(Head, Name, Arity),
    '$get_predicate_attribute'(M:Head, imported, M2), % predicate_property/2 requires
    !,                                                % P to be defined.
    dynamic(M2:Name/Arity).
xsb_dynamic_(PI, M) :-
    dynamic(M:PI).


		 /*******************************
		 *            BUILT-INS		*
		 *******************************/

%!  fail_if(:P)
%
%   Same as \+ (support XSB legacy code).  As the XSB manual claims this
%   is optimized we normally do goal expansion to \+/1.

fail_if(P) :-
    \+ P.

		 /*******************************
		 *      TABLING BUILT-INS	*
		 *******************************/

%!  not_exists(:P).
%!  sk_not(:P).
%
%   XSB tabled negation. According to the XSB manual, sk_not/1 is an old
%   name for not_exists/1. The predicates   tnot/1  and not_exists/1 are
%   not precisely the same. We ignore that for now.

not_exists(P) :-
    tnot(P).

sk_not(P) :-
    not_exists(P).


%!  xsb_findall(+Template, :Goal, -List) is det.
%
%   Alternative to findall/3 that is safe to   be used for tabling. This
%   is a temporary hack  as  the   findall/3  support  predicates cannot
%   handle suspension from inside the findall   goal  because it assumes
%   perfect nesting of findall.

xsb_findall(T, G, L) :-
    L0 = [dummy|_],
    Result = list(L0),
    (   call(G),
        duplicate_term(T, T2),
        NewLastCell = [T2|_],
        arg(1, Result, LastCell),
        nb_linkarg(2, LastCell, NewLastCell),
        nb_linkarg(1, Result, NewLastCell),
        fail
    ;   arg(1, Result, [_]),
        L0 = [_|L]
    ).


		 /*******************************
		 *           MESSAGES		*
		 *******************************/

:- multifile
    prolog:message//1.

prolog:message(xsb(not_in_module(File, Module, PI))) -->
    [ '~p, implementing ~p does not export ~p'-[File, Module, PI] ].
prolog:message(xsb(file_loaded_into_mismatched_module(File, Module))) -->
    [ 'File ~p defines module ~p'-[File, Module] ].
