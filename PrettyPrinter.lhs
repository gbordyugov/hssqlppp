
> module PrettyPrinter where

> import Text.PrettyPrint
> import Grammar

================================================================================

Public functions

> printSql :: [Statement] -> String
> printSql ast = render $ (vcat $ (map convStatement ast)) <> text "\n"

> printExpression :: Expression -> String
> printExpression ast = render $ convExp ast


================================================================================

Conversion routines - convert Sql asts into Docs

= Statements

> convStatement :: Statement -> Doc
> convStatement (SelectE e) = text "select" <+> convExp e <> statementEnd
> convStatement (Select l tb) = text "select" <+> convSelList l
>                               <+> text "from" <+> text tb <> statementEnd
> convStatement (CreateTable t atts) =
>     text "create table"
>     <+> text t <+> lparen
>     $+$ nest 2 (vcat (csv (map convAttDef atts)))
>     $+$ rparen <> statementEnd

> convStatement (Insert tb atts exps) = text "insert into" <+> text tb
>                                       <+> parens (hcatCsvMap text atts)
>                                       <+> text "values"
>                                       <+> parens (hcatCsvMap convExp exps)
>                                       <> statementEnd

> convStatement (Update tb scs wh) = text "update" <+> text tb <+> text "set"
>                                    <+> hcatCsvMap convSetClause scs
>                                    <+> case wh of
>                                         Nothing -> empty
>                                         Just w -> convWhere w
>                                    <> statementEnd

> convStatement (Delete tbl wh) = text "delete from" <+> text tbl
>                                 <+> case wh of
>                                            Nothing -> empty
>                                            Just w -> convWhere w
>                                 <> statementEnd

> convStatement (CreateFunction name args retType stmts) =
>     text "create function" <+> text name
>     <+> parens (hcatCsvMap convParamDef args)
>     <+> text "returns" <+> text retType <+> text "as" <+> text "$$"
>     $+$ text "begin"
>     $+$ (nest 2 (vcat $ map convStatement stmts))
>     $+$ text "end;"
>     $+$ text "$$ language plpgsql volatile" <> statementEnd

> convStatement NullStatement = text "null" <> statementEnd

> convStatement (CreateView name sel) =
>     text "create view" <+> text name <+> text "as"
>     $+$ (nest 2 (convStatement sel))

> statementEnd :: Doc
> statementEnd = semi <> newline

= Statement components

> convSetClause :: SetClause -> Doc
> convSetClause (SetClause att ex) = text att <+> text "=" <+> convExp ex

> convWhere :: Where -> Doc
> convWhere (Where ex) = text "where" <+> convExp ex

> convSelList :: SelectList -> Doc
> convSelList (SelectList l) = hcatCsvMap text l
> convSelList (Star) = text "*"

> convAttDef :: AttributeDef -> Doc
> convAttDef (AttributeDef n t ch) = text n <+> text t
>                                    <+> case ch of
>                                          Nothing -> empty
>                                          Just e -> text "check" <+> convExp e

> convParamDef :: ParamDef -> Doc
> convParamDef (ParamDef n t) = text n <+> text t

= Expressions

> convExp :: Expression -> Doc
> convExp (Identifier i) = text i
> convExp (IntegerL n) = integer n
> convExp (StringL s) = quotes $ text s
> convExp (FunctionCall i as) = text i <> parens (hcatCsvMap convExp as)
> convExp (BinaryOperatorCall op a b) = parens (convExp a <+> text (opToSymbol op) <+> convExp b)
> convExp (BooleanL b) = bool b
> convExp (InPredicate att expr) = text att <+> text "in" <+> parens (hcatCsvMap convExp expr)

= Utils

> csv :: [Doc] -> [Doc]
> csv l = punctuate comma l

> hcatCsv :: [Doc] -> Doc
> hcatCsv l = hcat $ csv l

> hcatCsvMap :: (a -> Doc) -> [a] -> Doc
> hcatCsvMap ex l = hcatCsv (map ex l)


> bool :: Bool -> Doc
> bool b = case b of
>            True -> text "true"
>            False -> text "false"

> newline :: Doc
> newline = text "\n"