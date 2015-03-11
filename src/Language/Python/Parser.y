{
module Language.Python.Parser (parse, parseRepl) where
import Control.Monad.Error
import Data.Either
import Data.List
import Data.Maybe

import Language.Python
import qualified Language.Python.Lexer as L
}

%tokentype  {L.Token}
%error      { parseError }

%name parseTokens file_input
%name parseLine single_input

%token
identifier  {L.Identifier $$}
literal     {L.Literal $$}
string      {L.StringLiteral $$}
NEWLINE     {L.Newline}
'+'         {L.Operator "+"}
'-'         {L.Operator "-"}
'*'         {L.Operator "*"}
'/'         {L.Operator "/"}
'|'         {L.Operator "|"}
'=='        {L.Operator "=="}
'!='        {L.Operator "!="}
'<'         {L.Operator "<"}
'<='        {L.Operator "<="}
'>'         {L.Operator ">"}
'>='        {L.Operator ">="}
'+='        {L.Delimiter "+="}
'-='        {L.Delimiter "-="}
'*='        {L.Delimiter "*="}
'/='        {L.Delimiter "/="}
'%='        {L.Delimiter "%="}
'&='        {L.Delimiter "&="}
'|='        {L.Delimiter "|="}
'^='        {L.Delimiter "^="}
'<<='       {L.Delimiter "<<="}
'>>='       {L.Delimiter ">>="}
'**='       {L.Delimiter "**="}
'//='       {L.Delimiter "//="}
'@'         {L.Delimiter "@"}
'%'         {L.Operator "%"}
'**'        {L.Operator "**"}
'//'        {L.Operator "//"}
'~'         {L.Operator "~"}
'^'         {L.Operator "^"}
'&'         {L.Operator "&"}
'<<'        {L.Operator "<<"}
'>>'        {L.Operator ">>"}
'.'         {L.Delimiter "."}
'['         {L.Delimiter "["}
']'         {L.Delimiter "]"}
'('         {L.Delimiter "("}
')'         {L.Delimiter ")"}
'{'         {L.Delimiter "{"}
'}'         {L.Delimiter "}"}
':'         {L.Delimiter ":"}
'='         {L.Delimiter "="}
';'         {L.Delimiter ";"}
','         {L.Delimiter ","}
INDENT      {L.Indent}
DEDENT      {L.Dedent}

AND         {L.Keyword "and"}
ASSERT      {L.Keyword "assert"}
AS          {L.Keyword "as"}
BREAK       {L.Keyword "break"}
CLASS       {L.Keyword "class"}
CONTINUE    {L.Keyword "continue"}
DEF         {L.Keyword "def"}
DEL         {L.Keyword "del"}
ELIF        {L.Keyword "elif"}
ELSE        {L.Keyword "else"}
EXCEPT      {L.Keyword "except"}
FALSE       {L.Keyword "False"}
FINALLY     {L.Keyword "finally"}
FOR         {L.Keyword "for"}
FROM        {L.Keyword "from"}
GLOBAL      {L.Keyword "global"}
IF          {L.Keyword "if"}
IMPORT      {L.Keyword "import"}
IN          {L.Keyword "in"}
IS          {L.Keyword "is"}
LAMBDA      {L.Keyword "lambda"}
NONE        {L.Keyword "None"}
NONLOCAL    {L.Keyword "nonlocal"}
NOT         {L.Keyword "not"}
OR          {L.Keyword "or"}
PASS        {L.Keyword "pass"}
RAISE       {L.Keyword "raise"}
RETURN      {L.Keyword "return"}
TRUE        {L.Keyword "True"}
TRY         {L.Keyword "try"}
WHILE       {L.Keyword "while"}
WITH        {L.Keyword "with"}
YIELD       {L.Keyword "yield"}

%left LAMBDA
%left IF ELSE
%left OR
%left AND
%left IN IS '<' '<=' '>' '>=' '!=' '=='
%left '|'
%left '^'
%left '&'
%left '<<' '>>'
%left '+' '-'
%left '*' '/' '//' '%'
%left POS NEG COMP
%left SPLAT
%right '**'

%%

or(p,q)
   : p      { $1 }
   | q      { $1 }

either(p,q)
   : p      { Left $1 }
   | q      { Right $1 }

opt(p)
   :        { Nothing }
   | p      { Just $1 }

rev_list1(p)
   : p               { [$1] }
   | rev_list1(p) p  { $2 : $1 }

many1(p)
   : rev_list1(p) { reverse $1 }

many0(p)
   : many1(p) { $1 }
   |         { [] }

sepOptEndBy(p,sep) 
   : sepByRev(p,sep) sep { reverse $1 }
   | sepByRev(p,sep) { reverse $1 }

sepBy(p,sep): sepByRev(p,sep) { reverse $1 }

sepBy0(p,sep)
    :                   { [] }
    | sepBy(p,sep)      { $1 }

sepByRev(p,sep)
   : p { [$1] }
   | sepByRev(p,sep) sep p { $3 : $1 }

exprOrTuple(p)
    : p     { $1 }
    | p ',' { TupleDef [$1] }
    | exprOrTupleTuple(p) opt(',') { TupleDef $1 }

exprOrTupleTuple(p)
    : p ',' p { [$1, $3] }
    | exprOrTupleTuple(p) ',' p { $1 ++ [$3] }

-- single_input: NEWLINE | simple_stmt | compound_stmt NEWLINE
single_input
    : NEWLINE                       { [Pass] }
    | simple_stmt                   { $1 }
    | compound_stmt NEWLINE         { [$1] }

-- file_input: (NEWLINE | stmt)* ENDMARKER
file_input
    : many0(either(NEWLINE, stmt))  { foldl' (++) [] (rights $1) }

-- eval_input: testlist NEWLINE* ENDMARKER
-- 
-- decorator: '@' dotted_name [ '(' [arglist] ')' ] NEWLINE
decorator
    : '@' dotted_name NEWLINE                       { Decorator $2 [] }
    | '@' dotted_name '(' arglist ')' NEWLINE       { Decorator $2 $4 }

-- decorators: decorator+
decorators
    : many1(decorator)      { $1 }

-- decorated: decorators (classdef | funcdef)
decorated
    : decorators or(classdef, funcdef)  { $2 }

-- funcdef: 'def' NAME parameters ['->' test] ':' suite
funcdef
    : DEF identifier parameters ':' suite { FuncDef $2 $3 $5 }

-- parameters: '(' [typedargslist] ')'
parameters
    : '(' sepBy0(parameter, ',') ')' { $2 }

parameter
    : identifier                { FormalParam $1 }
    | identifier '=' test       { DefaultParam $1 $3 }
    | '*' identifier            { SplatParam $2 }
    | '**' identifier           { DoubleSplatParam $2 }

-- typedargslist: (tfpdef ['=' test] (',' tfpdef ['=' test])* [','
--        ['*' [tfpdef] (',' tfpdef ['=' test])* [',' '**' tfpdef] | '**' tfpdef]]
--      |  '*' [tfpdef] (',' tfpdef ['=' test])* [',' '**' tfpdef] | '**' tfpdef)
-- tfpdef: NAME [':' test]
-- varargslist: (vfpdef ['=' test] (',' vfpdef ['=' test])* [','
--        ['*' [vfpdef] (',' vfpdef ['=' test])* [',' '**' vfpdef] | '**' vfpdef]]
--      |  '*' [vfpdef] (',' vfpdef ['=' test])* [',' '**' vfpdef] | '**' vfpdef)
varargslist
    : sepBy0(parameter, ',')    { $1 }

-- vfpdef: NAME
vfpdef
    : identifier    { $1 }

-- stmt: simple_stmt | compound_stmt
stmt
    : simple_stmt   { $1 }
    | compound_stmt { [$1] }

-- simple_stmt: small_stmt (';' small_stmt)* [';'] NEWLINE
simple_stmt
    : small_stmts opt(';') NEWLINE  { $1 }

small_stmts
    : small_stmt                    { [$1] }
    | small_stmts ';' small_stmt    { $3 : $1 }

-- small_stmt: (expr_stmt | del_stmt | pass_stmt | flow_stmt |
--              import_stmt | global_stmt | nonlocal_stmt | assert_stmt)
small_stmt
    : expr_stmt     { $1 }
    | del_stmt      { $1 }
    | pass_stmt     { $1 }
    | flow_stmt     { $1 }
    | import_stmt   { $1 }
    | global_stmt   { $1 }
    | nonlocal_stmt { $1 }
    | assert_stmt   { $1 }

-- expr_stmt: testlist_star_expr (augassign (yield_expr|testlist) |
--                      ('=' (yield_expr|testlist_star_expr))*)
expr_stmt
    : testlist_star_expr                                        { Expression $1 }
    | testlist_star_expr augassign or(yield_expr, testlist)     { handleAugAssignment $1 $2 $3 }
    | testlist_star_expr '=' or(yield_expr, testlist_star_expr) { Assignment $1 $3 }

-- testlist_star_expr: (test|star_expr) (',' (test|star_expr))* [',']
testlist_star_expr
    : exprOrTuple(or(test, star_expr)) { $1 }

-- augassign: ('+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' |
--             '<<=' | '>>=' | '**=' | '//=')
-- # For normal assignments, additional restrictions enforced by the interpreter
augassign
    : '+='      { ArithOp Add }
    | '-='      { ArithOp Sub }
    | '*='      { ArithOp Mul }
    | '/='      { ArithOp Div }
    | '%='      { ArithOp Mod }
    | '&='      { BitOp BitAnd }
    | '|='      { BitOp BitOr }
    | '^='      { BitOp BitXor }
    | '<<='     { BitOp LShift }
    | '>>='     { BitOp RShift }
    | '**='     { ArithOp Pow }
    | '//='     { ArithOp FDiv }

-- del_stmt: 'del' exprlist
del_stmt
    : DEL exprlist      { Del $2 }

-- pass_stmt: 'pass'
pass_stmt
    : PASS              { Pass }

-- flow_stmt: break_stmt | continue_stmt | return_stmt | raise_stmt | yield_stmt
flow_stmt
    : break_stmt        { $1 }
    | continue_stmt     { $1 }
    | return_stmt       { $1 }
    | raise_stmt        { $1 }
    | yield_stmt        { $1 }

-- break_stmt: 'break'
break_stmt
    : BREAK             { Break }

-- continue_stmt: 'continue'
continue_stmt
    : CONTINUE          { Continue }

-- return_stmt: 'return' [testlist]
return_stmt
    : RETURN opt(testlist)   { Return $ maybe (Constant ConstantNone) id $2 }

-- yield_stmt: yield_expr
yield_stmt
    : yield_expr        { Expression $1 }

-- raise_stmt: 'raise' [test ['from' test]]
raise_stmt
    : RAISE                 { Reraise }
    | RAISE test            { Raise $2 (Constant ConstantNone) }
    | RAISE test FROM test  { Raise $2 $4 }

-- import_stmt: import_name | import_from
import_stmt
    : import_name               { $1 }
    | import_from               { $1 }

-- import_name: 'import' dotted_as_names
import_name
    : IMPORT dotted_as_names    { Import $2 }

-- # note below: the ('.' | '...') is necessary because '...' is tokenized as ELLIPSIS
-- import_from: ('from' (('.' | '...')* dotted_name | ('.' | '...')+)
--               'import' ('*' | '(' import_as_names ')' | import_as_names))
import_from
    : FROM from_import IMPORT from_import_items { ImportFrom $2 $4 }

from_import
    : many0('.') dotted_name    { RelativeImport (length $1) $2 }
    | many1('.')                { RelativeImport (length $1) Glob }

from_import_items
    : '*'                       { [Glob] }
    | '(' import_as_names ')'   { $2 }
    | import_as_names           { $1 }

-- import_as_name: NAME ['as' NAME]
import_as_name
    : identifier                    { Name $1 }
    | identifier AS identifier      { As (Name $1) (Name $3) }

-- dotted_as_name: dotted_name ['as' NAME]
dotted_as_name
    : dotted_name                   { $1 }
    | dotted_name AS identifier     { As $1 (Name $3) }

-- import_as_names: import_as_name (',' import_as_name)* [',']
import_as_names
    : sepOptEndBy(import_as_name, ',')  { $1 }

-- dotted_as_names: dotted_as_name (',' dotted_as_name)*
dotted_as_names
    : sepBy(dotted_as_name, ',')    { $1 }

-- dotted_name: NAME ('.' NAME)*
dotted_name
    : sepBy(identifier, '.')        { Name $ (intercalate "." $1) }

-- global_stmt: 'global' NAME (',' NAME)*
global_stmt
    : GLOBAL sepBy(identifier, ',') { Global $2 }

-- nonlocal_stmt: 'nonlocal' NAME (',' NAME)*
nonlocal_stmt
    : NONLOCAL sepBy(identifier, ',')   { Nonlocal $ names $2 }

-- assert_stmt: 'assert' test [',' test]
assert_stmt
    : ASSERT test           { Assert $2 (Name "AssertionError") }
    | ASSERT test ',' test  { Assert $2 $4 }

-- compound_stmt: if_stmt | while_stmt | for_stmt | try_stmt | with_stmt | funcdef | classdef | decorated
compound_stmt
    : if_stmt       { $1 }
    | while_stmt    { $1 }
    | for_stmt      { $1 }
    | try_stmt      { $1 }
    | with_stmt     { $1 }
    | funcdef       { $1 }
    | classdef      { $1 }
    | decorated     { $1 }

-- if_stmt: 'if' test ':' suite ('elif' test ':' suite)* ['else' ':' suite]
if_stmt
    : IF test ':' suite many0(elif_clause) else_clause  { If ((IfClause $2 $4):$5) $6 }

elif_clause
    : ELIF test ':' suite { IfClause $2 $4 }

else_clause
    :                   { [] }
    | ELSE ':' suite    { $3 }

-- while_stmt: 'while' test ':' suite ['else' ':' suite]
while_stmt
    : WHILE test ':' suite                  { While $2 $4 [] }
    | WHILE test ':' suite ELSE ':' suite   { While $2 $4 $7 }

-- for_stmt: 'for' exprlist 'in' testlist ':' suite ['else' ':' suite]
for_stmt
    : FOR exprlist IN testlist ':' suite                { For $2 $4 $6 [] }
    | FOR exprlist IN testlist ':' suite ELSE ':' suite { For $2 $4 $6 $9 }

-- try_stmt: ('try' ':' suite
--            ((except_clause ':' suite)+
--             ['else' ':' suite]
--             ['finally' ':' suite] |
--            'finally' ':' suite))
try_stmt
    : TRY ':' suite many1(except_clauses) else_clause finally_clause    { Try $4 $3 $5 $6 }
    | TRY ':' suite FINALLY ':' suite                                   { Try [] $3 [] $6 }

except_clauses
    : except_clause ':' suite   { $1 $3 }

finally_clause
    :                           { [] }
    | FINALLY ':' suite         { $3 }

-- with_stmt: 'with' with_item (',' with_item)*  ':' suite
with_stmt
    : WITH sepBy(with_item, ',') ':' suite  { With $2 $4 }

-- with_item: test ['as' expr]
with_item
    : test                  { $1 }
    | test AS expr          { As $1 $3 }

-- # NB compile.c makes sure that the default except clause is last
-- except_clause: 'except' [test ['as' NAME]]
except_clause
    : EXCEPT                    { ExceptClause (Name "BaseException") "" }
    | EXCEPT test               { ExceptClause $2 "" }
    | EXCEPT test AS identifier { ExceptClause $2 $4 }

-- suite: simple_stmt | NEWLINE INDENT stmt+ DEDENT
suite
    : simple_stmt                       { $1 }
    | NEWLINE INDENT many1(stmt) DEDENT { concat $3 }

-- test: or_test ['if' or_test 'else' test] | lambdef
test
    : or_test                       { $1 }
    | or_test IF or_test ELSE test  { TernOp $3 $1 $5 }
    | lambdef                       { $1 }

-- test_nocond: or_test | lambdef_nocond
test_nocond
    : or_test               { $1 }
    | lambdef_nocond        { $1 }

-- lambdef: 'lambda' [varargslist] ':' test
lambdef
    : LAMBDA varargslist ':' test   { LambdaExpr $2 $4 }

-- lambdef_nocond: 'lambda' [varargslist] ':' test_nocond
lambdef_nocond
    : LAMBDA varargslist ':' test_nocond    { LambdaExpr $2 $4 }

-- or_test: and_test ('or' and_test)*
-- TODO: implement 0-n clauses
or_test
    : and_test              { $1 }
    | or_test OR and_test  { BinOp (BoolOp Or) $1 $3 }

-- and_test: not_test ('and' not_test)*
-- TODO: implement 0-n clauses
and_test
    : not_test              { $1 }
    | and_test AND not_test { BinOp (BoolOp And) $1 $3 }

-- not_test: 'not' not_test | comparison
-- TODO: implement 0-n clauses
not_test
    : NOT not_test          { UnaryOp Not $2 }
    | comparison            { $1 }

-- comparison: expr (comp_op expr)*
-- TODO: implement 0-n clauses
comparison
    : expr                  { $1 }
    | expr comp_op expr     { BinOp (CompOp $2) $1 $3 }

-- comp_op: '<'|'>'|'=='|'>='|'<='|'<>'|'!='|'in'|'not' 'in'|'is'|'is' 'not'
comp_op
    : '<'       { LessThan }
    | '>'       { GreaterThan }
    | '=='      { Eq }
    | '>='      { GreaterThanEq }
    | '<='      { LessThanEq }
    | '!='      { NotEq }
    | IN        { In }
    | NOT IN    { NotIn }
    | IS        { Is }
    | IS NOT    { IsNot }

-- star_expr: '*' expr
-- TODO: implement
star_expr
    : '*' expr      { undefined }

-- expr: xor_expr ('|' xor_expr)*
-- TODO: implement 0-n handling
expr
    : xor_expr                      { $1 }
    | xor_expr '|' xor_expr         { BinOp (BitOp BitOr) $1 $3 }

-- xor_expr: and_expr ('^' and_expr)*
-- TODO: implement 0-n handling
xor_expr
    : and_expr                      { $1 }
    | and_expr '^' and_expr         { BinOp (BitOp BitXor) $1 $3 }

-- and_expr: shift_expr ('&' shift_expr)*
-- TODO: implement 0-n handling
and_expr
    : shift_expr                    { $1 }
    | shift_expr '&' shift_expr     { BinOp (BitOp BitAnd) $1 $3 }

-- shift_expr: arith_expr (('<<'|'>>') arith_expr)*
-- TODO: implement 0-n handling
shift_expr
    : arith_expr                    { $1 }
    | arith_expr '<<' arith_expr    { BinOp (BitOp LShift) $1 $3 }
    | arith_expr '>>' arith_expr    { BinOp (BitOp RShift) $1 $3 }

-- arith_expr: term (('+'|'-') term)*
arith_expr
    : term                  { $1 }
    | arith_expr '+' term   { BinOp (ArithOp Add) $1 $3 }
    | arith_expr '-' term   { BinOp (ArithOp Sub) $1 $3 }

-- term: factor (('*'|'/'|'%'|'//') factor)*
term
    : factor            { $1 }
    | term '*' factor   { BinOp (ArithOp Mul) $1 $3 }
    | term '/' factor   { BinOp (ArithOp Div) $1 $3 }
    | term '%' factor   { BinOp (ArithOp Mod) $1 $3 }
    | term '//' factor  { BinOp (ArithOp FDiv) $1 $3 }

-- factor: ('+'|'-'|'~') factor | power
factor
    : '+' factor %prec POS  { UnaryOp Pos $2 }
    | '-' factor %prec NEG  { UnaryOp Neg $2 }
    | '~' factor %prec COMP { UnaryOp Complement $2 }
    | power                 { $1 }

-- power: atom trailer* ['**' factor]
power
    : atom many0(trailer)               { handleTrailers $1 $2 }
    | atom many0(trailer) '**' factor   { BinOp (ArithOp Pow) (handleTrailers $1 $2) $4 }

-- atom: ('(' [yield_expr|testlist_comp] ')' |
--        '[' [testlist_comp] ']' |
--        '{' [dictorsetmaker] '}' |
--        NAME | NUMBER | STRING+ | '...' | 'None' | 'True' | 'False')
atom
    : '(' opt(or(yield_expr, testlist_comp)) ')'    { maybe (TupleDef []) id $2 }
    | '[' opt(testlist_comp) ']'    { maybe (ListDef []) (\e -> ListDef $ expressionsOf e) $2 }
    | '{' opt(dictorsetmaker) '}'   { maybe (DictDef []) (\e -> e) $2 }
    | identifier                    { Name $1 }
    | literal                       { Constant $1 }
    | many1(string)                 { Constant $ ConstantString (foldl' (++) "" $1) }
    | NONE                          { Constant ConstantNone }
    | TRUE                          { Constant $ ConstantBool True }
    | FALSE                         { Constant $ ConstantBool False }

-- testlist_comp: (test|star_expr) ( comp_for | (',' (test|star_expr))* [','] )
testlist_comp
    : exprOrTuple(or(test, star_expr))  { $1 }
    | comp_for                          { undefined }

-- trailer: '(' [arglist] ')' | '[' subscriptlist ']' | '.' NAME
trailer
    : '(' arglist ')'       { TrailerCall $2 }
    | '[' subscriptlist ']' { TrailerSub $2 }
    | '.' identifier        { TrailerAttr $2 }

-- subscriptlist: subscript (',' subscript)* [',']
subscriptlist
    : exprOrTuple(subscript)        { $1 }

-- subscript: test | [test] ':' [test] [sliceop]
subscript
    : test      { $1 }
    | opt(test) ':' opt(test) opt(sliceop)  { handleSlice $1 $3 $4 }

-- sliceop: ':' [test]
sliceop
    : ':' opt(test)         { maybe (Constant ConstantNone) id $2 }

-- exprlist: (expr|star_expr) (',' (expr|star_expr))* [',']
exprlist
    : exprOrTuple(or(expr, star_expr))      { $1 }

-- testlist: test (',' test)* [',']
testlist
    : exprOrTuple(test)     { $1 }

-- dictorsetmaker: ( (test ':' test (comp_for | (',' test ':' test)* [','])) |
--                   (test (comp_for | (',' test)* [','])) )
dictorsetmaker
    : sepOptEndBy(set_item, ',')    { SetDef $1 }
    | sepOptEndBy(dict_item, ',')   { DictDef $1 }

set_item
    : test opt(comp_for)            { $1 }

dict_item
    : test ':' test opt(comp_for)   { ($1, $3)}

-- classdef: 'class' NAME ['(' [arglist] ')'] ':' suite
classdef
    : CLASS identifier base_classes ':' suite { ClassDef $2 $3 $5 }

base_classes
    :                   { [] }
    | '(' arglist ')'   { $2 }

-- arglist: (argument ',')* (argument [',']
--                          |'*' test (',' argument)* [',' '**' test] 
--                          |'**' test)
arglist
    : sepBy0(argitem, ',')                 { $1 }

argitem
    : argument      { $1 }
    | '*' test      { Star $2 }
    | '**' test     { DoubleStar $2 }

-- # The reason that keywords are test nodes instead of NAME is that using NAME
-- # results in an ambiguity. ast.c makes sure it's a NAME.
-- argument: test [comp_for] | test '=' test  # Really [keyword '='] test
argument
    : test opt(comp_for) { $1 }

-- comp_iter: comp_for | comp_if
comp_iter
    : or(comp_for, comp_if)  { $1 }

-- comp_for: 'for' exprlist 'in' or_test [comp_iter]
comp_for
    : FOR exprlist IN or_test opt(comp_iter) { undefined }

-- comp_if: 'if' test_nocond [comp_iter]
comp_if
    : IF test_nocond opt(comp_iter)     { undefined }
-- 
-- # not used in grammar, but may appear in "node" passed from Parser to Compiler
-- encoding_decl: NAME
-- 
-- yield_expr: 'yield' [yield_arg]
yield_expr
    : YIELD yield_arg       { Yield $2 }

-- yield_arg: 'from' test | testlist
yield_arg
    : FROM test             { From $2 }
    | testlist              { $1 }
{

data Trailer
    = TrailerCall [Expression]
    | TrailerAttr String
    | TrailerSub Expression
    | TrailerSlice
    deriving (Eq, Show)

expressionsOf (TupleDef exprs)  = exprs
expressionsOf expr              = [expr]

handleAugAssignment target op expr = Assignment target (BinOp op target expr)

handleSlice start stop stride = SliceDef (unwrap start) (unwrap stop) (unwrap stride)
  where
    unwrap arg = maybe (Constant ConstantNone) id arg

handleTrailers expr trailers = foldl' handleTrailer expr trailers
  where
    handleTrailer expr (TrailerCall args)   = Call expr args
    handleTrailer expr (TrailerAttr name)   = Attribute expr name
    handleTrailer expr (TrailerSub sub)     = Subscript expr sub

names :: [String] -> [Expression]
names xs = map Name xs

parse :: String -> Either String [Statement]
parse code = do
    case L.lex code of
        Right tokens    -> Right $ parseTokens tokens
        Left err        -> Left $ show err

parseRepl :: String -> Either String [Statement]
parseRepl code = do
    case L.lex code of
        Right tokens    -> Right $ parseLine tokens
        Left err        -> Left $ show err

parseError :: [L.Token] -> a
parseError t = error $ "Parse error: " ++ show t
}
