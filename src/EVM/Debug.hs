module EVM.Debug where

import EVM
import EVM.Types
import EVM.Exec
import EVM.Solidity

import Control.Arrow (second)

import Data.ByteString (ByteString)
import Data.Map (Map)
import Data.Text (Text)

import qualified Data.ByteString       as ByteString
import qualified Data.Map              as Map
import qualified Data.Vector.Storable   as Vector

import Control.Monad.State.Strict (execState)
import Control.Lens

import System.Console.Readline
import IPPrint.Colored (cpprint)

import Text.PrettyPrint.ANSI.Leijen

data Mode = Debug | Run

object :: [(Doc, Doc)] -> Doc
object xs =
  group $ lbrace
    <> line
    <> indent 2 (sep (punctuate (char ';') [k <+> equals <+> v | (k, v) <- xs]))
    <> line
    <> rbrace

prettyContract :: Contract -> Doc
prettyContract c =
  object $
    [ (text "codesize", int (ByteString.length (c ^. bytecode)))
    , (text "codehash", text (show (c ^. codehash)))
    , (text "balance", int (fromIntegral (c ^. balance)))
    , (text "nonce", int (fromIntegral (c ^. nonce)))
    , (text "code", text (show (ByteString.take 16 (c ^. bytecode))))
    , (text "storage", text (show (c ^. storage)))
    ]

prettyContracts :: Map Addr Contract -> Doc
prettyContracts x =
  object $
    (map (\(a, b) -> (text (show a), prettyContract b))
     (Map.toList x))

debugger :: Maybe SourceCache -> VM -> IO VM
debugger maybeCache vm = do
  -- cpprint (view state vm)
  cpprint ("pc", view (state . pc) vm)
  cpprint (view (state . stack) vm)
  -- cpprint (view logs vm)
  cpprint (vmOp vm)
  cpprint (opParams vm)
  cpprint (length (view frames vm))

  -- putDoc (prettyContracts (view (env . contracts) vm))

  case maybeCache of
    Nothing ->
      return ()
    Just cache ->
      case currentSrcMap vm of
        Nothing -> cpprint "no srcmap"
        Just sm -> cpprint (srcMapCode cache sm)

  if vm ^. result /= VMRunning
    then do
      print (vm ^. result)
      return vm
    else
    -- readline "(evm) " >>=
    return (Just "") >>=
      \case
        Nothing ->
          return vm
        Just line ->
          case words line of
            [] ->
              debugger maybeCache (execState exec1 vm)

            ["block"] ->
              do cpprint (view block vm)
                 debugger maybeCache vm

            ["storage"] ->
              do cpprint (view (env . contracts) vm)
                 debugger maybeCache vm

            ["contracts"] ->
              do putDoc (prettyContracts (view (env . contracts) vm))
                 debugger maybeCache vm

            -- ["disassemble"] ->
            --   do cpprint (mkCodeOps (view (state . code) vm))
            --      debugger maybeCache vm

            _  -> debugger maybeCache vm

currentSrcMap :: VM -> Maybe SrcMap
currentSrcMap vm =
  let
    c = vm ^?! env . contracts . ix (vm ^. state . contract)
    theOpIx = (c ^. opIxMap) Vector.! (vm ^. state . pc)
  in
    vm ^? env . solc . ix (c ^. codehash) . solcSrcmap . ix theOpIx

srcMapCodePos :: SourceCache -> SrcMap -> Maybe (Text, Int)
srcMapCodePos cache sm =
  fmap (second f) $ cache ^? sourceFiles . ix (srcMapFile sm)
  where
    f v = ByteString.count 0xa (ByteString.take (srcMapOffset sm - 1) v) + 1

srcMapCode :: SourceCache -> SrcMap -> Maybe ByteString
srcMapCode cache sm =
  fmap f $ cache ^? sourceFiles . ix (srcMapFile sm)
  where
    f (_, v) = ByteString.take (min 80 (srcMapLength sm)) (ByteString.drop (srcMapOffset sm) v)