module Main (main) where

import Test.Hspec

import qualified MCP.TypesSpec
import qualified MCP.ProtocolSpec
import qualified MCP.RouterSpec
import qualified Git.TypesAndHelpersSpec
import qualified Git.ToolsIntegrationSpec
import qualified Git.ToolUnitSpec
import qualified PropertySpec

main :: IO ()
main = hspec $ do
  describe "MCP.Types"           MCP.TypesSpec.spec
  describe "MCP.Protocol"        MCP.ProtocolSpec.spec
  describe "MCP.Router"          MCP.RouterSpec.spec
  describe "Git.TypesAndHelpers" Git.TypesAndHelpersSpec.spec
  describe "Git.ToolUnit"        Git.ToolUnitSpec.spec
  describe "Git.ToolsIntegration" Git.ToolsIntegrationSpec.spec
  describe "Properties"          PropertySpec.spec
