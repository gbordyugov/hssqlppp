
This code is an example to demonstrate loading a sql file, parsing it,
running a transform on the ast, then loading the result straight into
PostgreSQL.

> module Database.HsSqlPpp.Utils.DatabaseLoader
>     (loadAst
>     ) where
>
> import System.Directory
> import Control.Exception
> import Debug.Trace
>
> import Database.HsSqlPpp.PrettyPrinter
> import Database.HsSqlPpp.Ast as Ast
> import Database.HsSqlPpp.Utils.DbmsCommon

One small complication: haven't worked out how to send copy data from
haskell via HDBC or the pg lib, so use a dodgy hack to write inline
copy data to a temporary file to load from there.

> data HackStatement = Regular Statement
>                    | CopyHack Statement Statement
>                      deriving Show
>
> hackStatements :: [Statement] -> [HackStatement]
> hackStatements (st1@(Copy _ _ _ Stdin) :
>                 st2@(CopyData _ _) :
>                 sts) =
>   CopyHack st1 st2 : hackStatements sts
> hackStatements (st : sts) =
>   Regular st : hackStatements sts
> hackStatements [] = []

The main routine, which takes an AST and loads it into a database using HDBC.

> loadAst :: String -> [Statement] -> IO ()
> loadAst dbName ast =
>   withConn ("dbname=" ++ dbName) $ \conn ->
>        mapM_ (loadStatement conn) $ hackStatements ast
>   where
>     loadStatement conn (Regular st) =
>       runSqlCommand conn $ let a = printSql [st]
>                            in trace a $ a
>     loadStatement conn (CopyHack (Copy a tb cl Stdin) (CopyData _ s)) =
>       withTemporaryFile $ \tfn -> do
>         writeFile tfn s
>         tfn1 <- canonicalizePath tfn
>         loadStatement conn $ Regular $ Copy a tb cl $ CopyFilename tfn1
>     loadStatement _ x = error $ "got bad copy hack: " ++ show x


withtemporaryfile, part of the copy from stdin hack

can't use opentempfile since it gets locked and then the pg server/client lib can't
open the file for reading.

proper dodgy, needs work:

> withTemporaryFile :: (String -> IO c) -> IO c
> withTemporaryFile f = bracket (return ())
>                               (\_ -> removeFile "hssqlppptemp.temp")
>                               (\_ -> f "hssqlppptemp.temp")