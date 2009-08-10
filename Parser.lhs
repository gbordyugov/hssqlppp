> module Parser where

> import Text.ParserCombinators.Parsec
> import qualified Text.ParserCombinators.Parsec.Token as P
> import Text.ParserCombinators.Parsec.Language
> import qualified Text.Parsec.Prim
> import Control.Monad.Identity
> import Text.ParserCombinators.Parsec.Expr

> import Grammar

================================================================================

Top level parsing functions

Parse fully formed sql

> parseSql :: String -> Either ParseError [Statement]
> parseSql s = parse statements "(unknown)" s

> parseSqlFile :: String -> IO (Either ParseError [Statement])
> parseSqlFile f = parseFromFile statements f

Parse expression fragment, used for testing purposes

> parseExpression :: String -> Either ParseError Expression
> parseExpression s = parse expr' "" s
>   where expr' = do
>                 x <- expr
>                 eof
>                 return x

================================================================================

Parsing top level statements

> statements :: Text.Parsec.Prim.ParsecT [Char] () Identity [Statement]
> statements = do
>   whitespace
>   s <- many statement
>   eof
>   return s

> statement :: Text.Parsec.Prim.ParsecT [Char] () Identity Statement
> statement = do
>   select
>   <|> insert
>   <|> update
>   <|> delete
>   <|> try createTable
>   <|> try createFunction
>   <|> try createView
>   <|> nullStatement

statement types

> insert :: Text.Parsec.Prim.ParsecT String () Identity Statement
> insert = do
>   keyword "insert"
>   keyword "into"
>   tableName <- identifierString
>   atts <- parens $ commaSep1 identifierString
>   keyword "values"
>   exps <- parens $ commaSep1 expr
>   semi
>   return $ Insert tableName atts exps

> update :: Text.Parsec.Prim.ParsecT String () Identity Statement
> update = do
>   keyword "update"
>   tableName <- identifierString
>   keyword "set"
>   scs <- commaSep1 setClause
>   wh <- maybeP whereClause
>   semi
>   return $ Update tableName scs wh

> delete :: Text.Parsec.Prim.ParsecT String () Identity Statement
> delete = do
>   keyword "delete"
>   keyword "from"
>   tableName <- identifierString
>   wh <- maybeP whereClause
>   semi
>   return $ Delete tableName wh

> createTable :: Text.Parsec.Prim.ParsecT String () Identity Statement
> createTable = do
>   keyword "create"
>   keyword "table"
>   n <- identifierString
>   atts <- parens $ commaSep1 tableAtt
>   semi
>   return $ CreateTable n atts

> select :: Text.Parsec.Prim.ParsecT String () Identity Statement
> select = do
>   keyword "select"
>   (do try selExpression
>    <|> selQuerySpec)

> createFunction :: GenParser Char () Statement
> createFunction = do
>   keyword "create"
>   keyword "function"
>   fnName <- identifierString
>   params <- parens $ commaSep param
>   keyword "returns"
>   retType <- identifierString
>   keyword "as"
>   symbol "$$"
>   stmts <- functionBody
>   symbol "$$"
>   keyword "language"
>   keyword "plpgsql"
>   keyword "volatile"
>   semi
>   return $ CreateFunction fnName params retType stmts

> createView :: Text.Parsec.Prim.ParsecT String () Identity Statement
> createView = do
>   keyword "create"
>   keyword "view"
>   vName <- identifierString
>   keyword "as"
>   sel <- select
>   return $ CreateView vName sel

> nullStatement :: Text.Parsec.Prim.ParsecT String u Identity Statement
> nullStatement = do
>   keyword "null"
>   semi
>   return NullStatement

> selExpression :: Text.Parsec.Prim.ParsecT [Char] () Identity Statement
> selExpression = do
>   e <- expr
>   semi
>   return $ SelectE e

Statement components

> functionBody :: Text.Parsec.Prim.ParsecT [Char] () Identity [Statement]
> functionBody = do
>   keyword "begin"
>   stmts <- many statement
>   keyword "end"
>   semi
>   return stmts

> param :: Text.Parsec.Prim.ParsecT String () Identity ParamDef
> param = do
>   name <- identifierString
>   tp <- identifierString
>   return $ ParamDef name tp

> setClause :: Text.Parsec.Prim.ParsecT String () Identity SetClause
> setClause = do
>   ref <- identifierString
>   symbol "="
>   ex <- expr
>   return $ SetClause ref ex

> whereClause :: Text.Parsec.Prim.ParsecT String () Identity Where
> whereClause = do
>   keyword "where"
>   ex <- expr
>   return $ Where ex

> tableAtt :: Text.Parsec.Prim.ParsecT String () Identity AttributeDef
> tableAtt = do
>   name <- identifierString
>   typ <- identifierString
>   check <- maybeP (do
>                     keyword "check"
>                     expr)
>   return $ AttributeDef name typ check

> selQuerySpec :: Text.Parsec.Prim.ParsecT String () Identity Statement
> selQuerySpec = do
>   sl <- (do
>          symbol "*"
>          return Star
>         ) <|> selectList
>   keyword "from"
>   tb <- word
>   semi
>   return $ Select sl tb

> selectList :: Text.Parsec.Prim.ParsecT String () Identity SelectList
> selectList = do
>   liftM SelectList $ commaSep1 identifierString

================================================================================

expressions

> expr :: Parser Expression
> expr =
>   buildExpressionParser table factor
>   <?> "expression"

> factor :: GenParser Char () Expression
> factor  = parens expr
>           <|> stringLiteral
>           <|> integer
>           <|> try booleanLiteral
>           <|> try inPredicate
>           <|> try functionCall
>           <|> identifier
>           <?> "simple expression"

>   -- Specifies operator, associativity, precendence, and constructor to execute
>   -- and built AST with.
> table :: [[Operator Char u Expression]]
> table =
>       [ --[prefix "-" (BinaryOperatorCall Mult (IntegerL (-1)))]
>       --,
>        [binary "^" (BinaryOperatorCall Pow) AssocRight]
>       ,[binary "*" (BinaryOperatorCall Mult) AssocLeft
>        ,binary "/" (BinaryOperatorCall Div) AssocLeft
>        ,binary "=" (BinaryOperatorCall Eql) AssocLeft
>        ,binary "%" (BinaryOperatorCall Mod) AssocLeft]
>       ,[binary "+" (BinaryOperatorCall Plus) AssocLeft
>        ,binary "-" (BinaryOperatorCall Minus) AssocLeft]
>       ]
>     where
>       binary s f assoc
>          = Infix (symbol s >> return f) assoc
>       --prefix s f
>       --   = Prefix (symbol s >> return f)
>

> inPredicate :: Text.Parsec.Prim.ParsecT [Char] () Identity Expression
> inPredicate = do
>   vexp <- identifierString
>   keyword "in"
>   e <- parens $ commaSep1 expr
>   return $ InPredicate vexp e

> identifier :: Text.Parsec.Prim.ParsecT String () Identity Expression
> identifier = liftM Identifier identifierString

> booleanLiteral :: Text.Parsec.Prim.ParsecT String u Identity Expression
> booleanLiteral = do
>   x <- ((lexeme $ string "true")
>         <|> (lexeme $ string "false"))
>   return $ BooleanL (x == "true")

> integer :: Text.Parsec.Prim.ParsecT String u Identity Expression
> integer = liftM IntegerL $ lexeme $ P.integer lexer

> stringLiteral :: Text.Parsec.Prim.ParsecT String u Identity Expression
> stringLiteral = do
>   char '\''
>   name <- many (noneOf "'")
>   lexeme $ char '\''
>   return $ StringL name

> functionCall :: Text.Parsec.Prim.ParsecT String () Identity Expression
> functionCall = do
>   name <- identifierString
>   args <- parens $ commaSep factor
>   return $ FunctionCall name args



================================================================================

Utility parsers

> whitespace :: Text.Parsec.Prim.ParsecT String u Identity ()
> whitespace = skipMany ((space >> return ())
>                        <|> blockComment
>                        <|> lineComment)

> keyword :: String -> Text.Parsec.Prim.ParsecT String u Identity String
> keyword k = lexeme $ string k

> identifierString :: Parser String
> identifierString = do
>   s <- letter
>   p <- many (alphaNum <|> char '_')
>   whitespace
>   return $ s : p

> word :: Parser String
> word = lexeme (many1 letter)

> maybeP :: GenParser tok st a
>           -> Text.Parsec.Prim.ParsecT [tok] st Identity (Maybe a)
> maybeP p = do
>   (do a <- try p
>       return $ Just a)
>   <|> return Nothing

> blockComment :: Text.Parsec.Prim.ParsecT [Char] st Identity ()
> blockComment = do
>   try (char '/' >> char '*')
>   manyTill anyChar (try (string "*/"))
>   return ()

> lineComment :: Text.Parsec.Prim.ParsecT [Char] st Identity ()
> lineComment = do
>   try (char '-' >> char '-')
>   manyTill anyChar ((try (char '\n') >> return ()) <|> eof)
>   return ()

================================================================================

pass through stuff from parsec

> lexer :: P.GenTokenParser String u Identity
> lexer = P.makeTokenParser (haskellDef
>                            { reservedOpNames = ["*","/","+","-"],
>                              commentStart = "/*",
>                              commentEnd = "*/",
>                              commentLine = "--"
>                            })

> lexeme :: Text.Parsec.Prim.ParsecT String u Identity a
>           -> Text.Parsec.Prim.ParsecT String u Identity a
> lexeme = P.lexeme lexer

> commaSep :: Text.Parsec.Prim.ParsecT String u Identity a
>             -> Text.Parsec.Prim.ParsecT String u Identity [a]
> commaSep = P.commaSep lexer

> commaSep1 :: Text.Parsec.Prim.ParsecT String u Identity a
>             -> Text.Parsec.Prim.ParsecT String u Identity [a]
> commaSep1 = P.commaSep lexer


> semi :: Text.Parsec.Prim.ParsecT String u Identity String
> semi = P.semi lexer

> parens :: Text.Parsec.Prim.ParsecT String u Identity a
>           -> Text.Parsec.Prim.ParsecT String u Identity a
> parens = P.parens lexer

> symbol :: String -> Text.Parsec.Prim.ParsecT String u Identity String
> symbol = P.symbol lexer