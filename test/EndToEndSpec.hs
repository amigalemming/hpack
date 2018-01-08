{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ConstraintKinds #-}
module EndToEndSpec (spec) where

import           Prelude hiding (writeFile)
import qualified Prelude

import           Helper
import           Test.HUnit

import           System.Directory (canonicalizePath)
import           Data.Maybe
import           Data.List
import           Data.String.Interpolate
import           Data.String.Interpolate.Util

import qualified Hpack.Render as Hpack
import           Hpack.Config (packageConfig, readPackageConfig)
import           Hpack.Render.Hints (FormattingHints(..), sniffFormattingHints)

writeFile :: FilePath -> String -> IO ()
writeFile file c = touch file >> Prelude.writeFile file c

spec :: Spec
spec = around_ (inTempDirectoryNamed "foo") $ do
  describe "hpack" $ do
    it "ignores fields that start with an underscore" $ do
      [i|
      _foo:
        bar: 23
      library: {}
      |] `shouldRenderTo` library [i|
      other-modules:
          Paths_foo
      |]

    describe "github" $ do
      it "accepts owner/repo" $ do
        [i|
        github: hspec/hspec
        |] `shouldRenderTo` package [i|
        homepage: https://github.com/hspec/hspec#readme
        bug-reports: https://github.com/hspec/hspec/issues
        source-repository head
          type: git
          location: https://github.com/hspec/hspec
        |]

      it "accepts owner/repo/path" $ do
        [i|
        github: hspec/hspec/hspec-core
        |] `shouldRenderTo` package [i|
        homepage: https://github.com/hspec/hspec#readme
        bug-reports: https://github.com/hspec/hspec/issues
        source-repository head
          type: git
          location: https://github.com/hspec/hspec
          subdir: hspec-core
        |]

    describe "homepage" $ do
      it "accepts homepage URL" $ do
        [i|
        homepage: https://example.com/
        |] `shouldRenderTo` package [i|
        homepage: https://example.com/
        |]

      context "with github" $ do
        it "gives homepage URL precedence" $ do
          [i|
          github: hspec/hspec
          homepage: https://example.com/
          |] `shouldRenderTo` package [i|
          homepage: https://example.com/
          bug-reports: https://github.com/hspec/hspec/issues
          source-repository head
            type: git
            location: https://github.com/hspec/hspec
          |]

        it "omits homepage URL if it is null" $ do
          [i|
          github: hspec/hspec
          homepage: null
          |] `shouldRenderTo` package [i|
          bug-reports: https://github.com/hspec/hspec/issues
          source-repository head
            type: git
            location: https://github.com/hspec/hspec
          |]

    describe "bug-reports" $ do
      it "accepts bug-reports URL" $ do
        [i|
        bug-reports: https://example.com/
        |] `shouldRenderTo` package [i|
        bug-reports: https://example.com/
        |]

      context "with github" $ do
        it "gives bug-reports URL precedence" $ do
          [i|
          github: hspec/hspec
          bug-reports: https://example.com/
          |] `shouldRenderTo` package [i|
          homepage: https://github.com/hspec/hspec#readme
          bug-reports: https://example.com/
          source-repository head
            type: git
            location: https://github.com/hspec/hspec
          |]

        it "omits bug-reports URL if it is null" $ do
          [i|
          github: hspec/hspec
          bug-reports: null
          |] `shouldRenderTo` package [i|
          homepage: https://github.com/hspec/hspec#readme
          source-repository head
            type: git
            location: https://github.com/hspec/hspec
          |]

    describe "defaults" $ do
      it "accepts global defaults" $ do
        writeFile "defaults/sol/hpack-template/2017/defaults.yaml" [i|
        default-extensions:
          - RecordWildCards
          - DeriveFunctor
        |]

        [i|
        defaults:
          github: sol/hpack-template
          path: defaults.yaml
          ref: "2017"
        library: {}
        |] `shouldRenderTo` library_ [i|
        default-extensions: RecordWildCards DeriveFunctor
        |]

      it "accepts library defaults" $ do
        writeFile "defaults/sol/hpack-template/2017/defaults.yaml" [i|
        exposed-modules: Foo
        |]

        [i|
        library:
          defaults:
            github: sol/hpack-template
            path: defaults.yaml
            ref: "2017"
        |] `shouldRenderTo` library [i|
        exposed-modules:
            Foo
        other-modules:
            Paths_foo
        |]

      it "accepts a list of defaults" $ do
        writeFile "defaults/foo/bar/v1/.hpack/defaults.yaml" "default-extensions: RecordWildCards"
        writeFile "defaults/foo/bar/v2/.hpack/defaults.yaml" "default-extensions: DeriveFunctor"
        [i|
        defaults:
          - foo/bar@v1
          - foo/bar@v2
        library: {}
        |] `shouldRenderTo` library_ [i|
        default-extensions: RecordWildCards DeriveFunctor
        |]

      it "accepts defaults recursively" $ do
        writeFile "defaults/foo/bar/v1/.hpack/defaults.yaml" "defaults: foo/bar@v2"
        writeFile "defaults/foo/bar/v2/.hpack/defaults.yaml" "default-extensions: DeriveFunctor"
        [i|
        defaults: foo/bar@v1
        library: {}
        |] `shouldRenderTo` library_ [i|
        default-extensions: DeriveFunctor
        |]

      it "fails on cyclic defaults" $ do
        let
          file1 = "defaults/foo/bar/v1/.hpack/defaults.yaml"
          file2 = "defaults/foo/bar/v2/.hpack/defaults.yaml"
        writeFile file1 "defaults: foo/bar@v2"
        writeFile file2 "defaults: foo/bar@v1"
        canonic1 <- canonicalizePath file1
        canonic2 <- canonicalizePath file2
        [i|
        defaults: foo/bar@v1
        library: {}
        |] `shouldFailWith` [i|cycle in defaults (#{canonic1} -> #{canonic2} -> #{canonic1})|]

      it "fails if defaults don't exist" $ do
        pending
        [i|
        defaults:
          github: sol/foo
          ref: bar
        library: {}
        |] `shouldFailWith` "Invalid value for \"defaults\"! File https://raw.githubusercontent.com/sol/foo/bar/.hpack/defaults.yaml does not exist!"

      it "fails on parse error" $ do
        let file = joinPath ["defaults", "sol", "hpack-template", "2017", "defaults.yaml"]
        writeFile file "[]"
        [i|
        defaults:
          github: sol/hpack-template
          path: defaults.yaml
          ref: "2017"
        library: {}
        |] `shouldFailWith` (file ++ ": Error while parsing $ - expected Object, encountered Array")

      it "warns on unknown fields" $ do
        let file = joinPath ["defaults", "sol", "hpack-template", "2017", "defaults.yaml"]
        writeFile file "foo: bar"
        [i|
        name: foo
        defaults:
          github: sol/hpack-template
          path: defaults.yaml
          ref: "2017"
          bar: baz
        library: {}
        |] `shouldWarn` [
            "package.yaml: Ignoring unrecognized field $.defaults.bar"
          , file ++ ": Ignoring unrecognized field $.foo"
          ]
    context "with local defaults" $ do
      it "accepts defaults from local files" $ do
        writeFile "defaults.yaml" [i|
        default-extensions:
          - RecordWildCards
          - DeriveFunctor
        |]
        [i|
        defaults:
          local: defaults.yaml
        library: {}
        |] `shouldRenderTo` library [i|
        other-modules:
            Paths_foo
        default-extensions: RecordWildCards DeriveFunctor
        |]

      it "accepts relative local defaults" $ do
        writeFile "../foo/bar/defaults.yaml" [i|
        default-extensions:
          - RecordWildCards
          - DeriveFunctor
        |]
        [i|
        defaults:
          local: ../foo/bar/defaults.yaml
        library: {}
        |] `shouldRenderTo` library [i|
        other-modules:
            Paths_foo
        default-extensions: RecordWildCards DeriveFunctor
        |]

      it "fails if local defaults don't exist" $ do
        [i|
        defaults:
          local: some-non-existent-file.yaml
        library: {}
        |] `shouldFailWith` "Invalid value for \"defaults\"! Local file some-non-existent-file.yaml does not exist!"

      it "fails on parse error" $ do
        writeFile "defaults.yaml" "[]"
        [i|
        defaults:
          local: defaults.yaml
        library: {}
        |] `shouldFailWith` ("defaults.yaml: Error while parsing $ - expected Object, encountered Array")

      it "warns on unknown fields in local defaults" $ do
        writeFile "defaults.yaml" "foo: bar"
        [i|
        defaults:
          local: defaults.yaml
          bar: b
        name: foo
        library: {}
        |] `shouldWarn` [
            "defaults.yaml: Ignoring unrecognized field $.foo"
          , "package.yaml: Ignoring unrecognized field $.defaults.bar"
          ]

      it "fails if both github and local fields are present" $ do
        writeFile "defaults.yaml" "{}"
        [i|
        defaults:
          local: defaults.yaml
          github: foo/bar
        library: {}
        |] `shouldFailWith` ("package.yaml: Error while parsing $.defaults - both \"github\" and \"local\" are present; please use one or the other.")

    describe "version" $ do
      it "accepts string" $ do
        [i|
        version: 0.1.0
        |] `shouldRenderTo` (package "") {packageVersion = "0.1.0"}

      it "accepts number" $ do
        [i|
        version: 0.1
        |] `shouldRenderTo` (package [i|
        |]) {packageVersion = "0.1"}

      it "rejects other values" $ do
        [i|
        version: {}
        |] `shouldFailWith` "package.yaml: Error while parsing $.version - expected Number or String, encountered Object"

    describe "build-type" $ do
      it "accept Simple" $ do
        [i|
        build-type: Simple
        |] `shouldRenderTo` (package "") {packageBuildType = "Simple"}

      it "accept Configure" $ do
        [i|
        build-type: Configure
        |] `shouldRenderTo` (package "") {packageBuildType = "Configure"}

      it "accept Make" $ do
        [i|
        build-type: Make
        |] `shouldRenderTo` (package "") {packageBuildType = "Make"}

      it "accept Custom" $ do
        [i|
        build-type: Custom
        |] `shouldRenderTo` (package "") {packageBuildType = "Custom"}

      it "rejects invalid values" $ do
        [i|
        build-type: foo
        |] `shouldFailWith` "package.yaml: Error while parsing $.build-type - expected one of Simple, Configure, Make, or Custom"


    describe "extra-doc-files" $ do
      it "accepts a list of files" $ do
        touch "CHANGES.markdown"
        touch "README.markdown"
        [i|
        extra-doc-files:
          - CHANGES.markdown
          - README.markdown
        |] `shouldRenderTo` (package [i|
        extra-doc-files:
            CHANGES.markdown
            README.markdown
        |]) {packageCabalVersion = ">= 1.18"}

      it "accepts glob patterns" $ do
        touch "CHANGES.markdown"
        touch "README.markdown"
        [i|
        extra-doc-files:
          - "*.markdown"
        |] `shouldRenderTo` (package [i|
        extra-doc-files:
            CHANGES.markdown
            README.markdown
        |]) {packageCabalVersion = ">= 1.18"}

      it "warns if a glob pattern does not match anything" $ do
        [i|
        name: foo
        extra-doc-files:
          - "*.markdown"
        |] `shouldWarn` ["Specified pattern \"*.markdown\" for extra-doc-files does not match any files"]

    describe "dependencies" $ do
      it "accepts single dependency" $ do
        [i|
        executable:
          dependencies: base
        |] `shouldRenderTo` executable_ "foo" [i|
        build-depends:
            base
        |]

      it "accepts list of dependencies" $ do
        [i|
        executable:
          dependencies:
            - base
            - transformers
        |] `shouldRenderTo` executable_ "foo" [i|
        build-depends:
            base
          , transformers
        |]

      context "with both global and section specific dependencies" $ do
        it "combines dependencies" $ do
          [i|
          dependencies:
            - base
          executable:
            dependencies: hspec
          |] `shouldRenderTo` executable_ "foo" [i|
          build-depends:
              base
            , hspec
          |]

        it "gives section specific dependencies precedence" $ do
          [i|
          dependencies:
            - base
          executable:
            dependencies: base >= 2
          |] `shouldRenderTo` executable_ "foo" [i|
          build-depends:
              base >=2
          |]

    describe "pkg-config-dependencies" $ do
      it "accepts pkg-config-dependencies" $ do
        [i|
        pkg-config-dependencies:
          - QtWebKit
          - weston
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        pkgconfig-depends:
            QtWebKit
          , weston
        |]

    describe "include-dirs" $ do
      it "accepts include-dirs" $ do
        [i|
        include-dirs:
          - foo
          - bar
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        include-dirs:
            foo
            bar
        |]

    describe "install-includes" $ do
      it "accepts install-includes" $ do
        [i|
        install-includes:
          - foo.h
          - bar.h
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        install-includes:
            foo.h
            bar.h
        |]

    describe "js-sources" $ before_ (touch "foo.js" >> touch "jsbits/bar.js") $ do
      it "accepts js-sources" $ do
        [i|
        executable:
          js-sources:
            - foo.js
            - jsbits/*.js
        |] `shouldRenderTo` executable_ "foo" [i|
        js-sources:
            foo.js
            jsbits/bar.js
        |]

      it "accepts global js-sources" $ do
        [i|
        js-sources:
          - foo.js
          - jsbits/*.js
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        js-sources:
            foo.js
            jsbits/bar.js
        |]
    describe "extra-lib-dirs" $ do
      it "accepts extra-lib-dirs" $ do
        [i|
        extra-lib-dirs:
          - foo
          - bar
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        extra-lib-dirs:
            foo
            bar
        |]

    describe "extra-libraries" $ do
      it "accepts extra-libraries" $ do
        [i|
        extra-libraries:
          - foo
          - bar
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        extra-libraries:
            foo
            bar
        |]

    describe "extra-frameworks-dirs" $ do
      it "accepts extra-frameworks-dirs" $ do
        [i|
        extra-frameworks-dirs:
          - foo
          - bar
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        extra-frameworks-dirs:
            foo
            bar
        |]

    describe "frameworks" $ do
      it "accepts frameworks" $ do
        [i|
        frameworks:
          - foo
          - bar
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        frameworks:
            foo
            bar
        |]

    describe "c-sources" $ before_ (touch "cbits/foo.c" >> touch "cbits/bar.c") $ do
      context "with internal-libraries" $ do
        it "warns when a glob pattern does not match any files" $ do
          [i|
          name: foo
          internal-libraries:
            bar:
              c-sources: foo/*.c
          |] `shouldWarn` pure "Specified pattern \"foo/*.c\" for c-sources does not match any files"

      context "with library" $ do
        it "accepts global c-sources" $ do
          [i|
          c-sources: cbits/*.c
          library: {}
          |] `shouldRenderTo` library_ [i|
          c-sources:
              cbits/bar.c
              cbits/foo.c
          |]

        it "accepts c-sources" $ do
          [i|
          library:
            c-sources: cbits/*.c
          |] `shouldRenderTo` library_ [i|
          c-sources:
              cbits/bar.c
              cbits/foo.c
          |]

        it "accepts c-sources in conditional" $ do
          [i|
          library:
            when:
              condition: os(windows)
              c-sources: cbits/*.c
          |] `shouldRenderTo` library_ [i|
          if os(windows)
            c-sources:
                cbits/bar.c
                cbits/foo.c
          |]

      context "with executables" $ do
        it "accepts global c-sources" $ do
          [i|
          c-sources: cbits/*.c
          executables:
            foo: {}
          |] `shouldRenderTo` executable_ "foo" [i|
          c-sources:
              cbits/bar.c
              cbits/foo.c
          |]

        it "accepts c-sources" $ do
          [i|
          executables:
            foo:
              c-sources: cbits/*.c
          |] `shouldRenderTo` executable_ "foo" [i|
          c-sources:
              cbits/bar.c
              cbits/foo.c
          |]

    describe "custom-setup" $ do
      it "warns on unknown fields" $ do
        [i|
        name: foo
        custom-setup:
          foo: 1
          bar: 2
        |] `shouldWarn` [
            "package.yaml: Ignoring unrecognized field $.custom-setup.bar"
          , "package.yaml: Ignoring unrecognized field $.custom-setup.foo"
          ]

      it "accepts dependencies" $ do
        [i|
        custom-setup:
          dependencies:
            - base
        |] `shouldRenderTo` customSetup [i|
        setup-depends:
            base
        |]

      it "leaves build-type alone, if it exists" $ do
        [i|
        build-type: Make
        custom-setup:
          dependencies:
            - base
        |] `shouldRenderTo` (customSetup [i|
        setup-depends:
            base
        |]) {packageBuildType = "Make"}

    describe "library" $ do
      it "accepts reexported-modules" $ do
        [i|
        library:
          reexported-modules: Baz
        |] `shouldRenderTo` (library_ [i|
          reexported-modules:
              Baz
        |]) {packageCabalVersion = ">= 1.22"}

      it "accepts signatures" $ do
        [i|
        library:
          signatures: Foo
        |] `shouldRenderTo` (library_ [i|
          signatures:
              Foo
        |]) {packageCabalVersion = ">= 2.0"}

      context "when package.yaml contains duplicate modules" $ do
        it "generates a cabal file with duplicate modules" $ do
          -- garbage in, garbage out
          [i|
          library:
            exposed-modules: Foo
            other-modules: Foo
          |] `shouldRenderTo` library [i|
          exposed-modules:
              Foo
          other-modules:
              Foo
          |]

      context "when inferring modules" $ do
        context "with exposed-modules" $ do
          it "infers other-modules" $ do
            touch "src/Foo.hs"
            touch "src/Bar.hs"
            [i|
            library:
              source-dirs: src
              exposed-modules: Foo
            |] `shouldRenderTo` library [i|
            hs-source-dirs:
                src
            exposed-modules:
                Foo
            other-modules:
                Bar
                Paths_foo
            |]

        context "with other-modules" $ do
          it "infers exposed-modules" $ do
            touch "src/Foo.hs"
            touch "src/Bar.hs"
            [i|
            library:
              source-dirs: src
              other-modules: Bar
            |] `shouldRenderTo` library [i|
            hs-source-dirs:
                src
            exposed-modules:
                Foo
            other-modules:
                Bar
            |]

        context "with both exposed-modules and other-modules" $ do
          it "doesn't infer any modules" $ do
            touch "src/Foo.hs"
            touch "src/Bar.hs"
            [i|
            library:
              source-dirs: src
              exposed-modules: Foo
              other-modules: Bar
            |] `shouldRenderTo` library [i|
            hs-source-dirs:
                src
            exposed-modules:
                Foo
            other-modules:
                Bar
            |]

        context "with neither exposed-modules nor other-modules" $ do
          it "infers exposed-modules" $ do
            touch "src/Foo.hs"
            touch "src/Bar.hs"
            [i|
            library:
              source-dirs: src
            |] `shouldRenderTo` library [i|
            hs-source-dirs:
                src
            exposed-modules:
                Bar
                Foo
            other-modules:
                Paths_foo
            |]

        context "with a conditional" $ do
          it "doesn't infer any modules mentioned in that conditional" $ do
            touch "src/Foo.hs"
            touch "src/Bar.hs"
            [i|
            library:
              source-dirs: src
              when:
                condition: os(windows)
                exposed-modules:
                  - Foo
                  - Paths_foo
            |] `shouldRenderTo` library [i|
            hs-source-dirs:
                src
            if os(windows)
              exposed-modules:
                  Foo
                  Paths_foo
            exposed-modules:
                Bar
            |]

          context "with a source-dir inside the conditional" $ do
            it "infers other-modules" $ do
              touch "windows/Foo.hs"
              [i|
              library:
                when:
                  condition: os(windows)
                  source-dirs: windows
              |] `shouldRenderTo` library [i|
              other-modules:
                  Paths_foo
              if os(windows)
                other-modules:
                    Foo
                hs-source-dirs:
                    windows
              |]

            it "does not infer outer modules" $ do
              touch "windows/Foo.hs"
              touch "unix/Foo.hs"
              [i|
              library:
                exposed-modules: Foo
                when:
                  condition: os(windows)
                  then:
                    source-dirs: windows/
                  else:
                    source-dirs: unix/

              |] `shouldRenderTo` library [i|
              exposed-modules:
                  Foo
              other-modules:
                  Paths_foo
              if os(windows)
                hs-source-dirs:
                    windows/
              else
                hs-source-dirs:
                    unix/
              |]

        context "with generated modules" $ do
          it "includes generated modules in autogen-modules" $ do
            [i|
            library:
              generated-exposed-modules: Foo
              generated-other-modules: Bar
            |] `shouldRenderTo` (library [i|
            exposed-modules:
                Foo
            other-modules:
                Paths_foo
                Bar
            autogen-modules:
                Foo
                Bar
            |]) {packageCabalVersion = ">= 2.0"}

          it "does not infer any mentioned generated modules" $ do
            touch "src/Exposed.hs"
            touch "src/Other.hs"
            [i|
            library:
              source-dirs: src
              generated-exposed-modules: Exposed
              generated-other-modules: Other
            |] `shouldRenderTo` (library [i|
            hs-source-dirs:
                src
            exposed-modules:
                Exposed
            other-modules:
                Paths_foo
                Other
            autogen-modules:
                Exposed
                Other
            |]) {packageCabalVersion = ">= 2.0"}

          it "does not infer any generated modules mentioned inside conditionals" $ do
            touch "src/Exposed.hs"
            touch "src/Other.hs"
            [i|
            library:
              source-dirs: src
              when:
                condition: os(windows)
                generated-exposed-modules: Exposed
                generated-other-modules: Other
            |] `shouldRenderTo` (library [i|
            other-modules:
                Paths_foo
            hs-source-dirs:
                src
            if os(windows)
              exposed-modules:
                  Exposed
              other-modules:
                  Other
              autogen-modules:
                  Other
                  Exposed
            |]) {packageCabalVersion = ">= 2.0"}

    describe "internal-libraries" $ do
      it "accepts internal-libraries" $ do
        touch "src/Foo.hs"
        [i|
        internal-libraries:
          bar:
            source-dirs: src
          |] `shouldRenderTo` internalLibrary "bar" [i|
          exposed-modules:
              Foo
          other-modules:
              Paths_foo
          hs-source-dirs:
              src
          |]

      it "warns on unknown fields" $ do
        [i|
        name: foo
        internal-libraries:
          bar:
            baz: 42
        |] `shouldWarn` pure "package.yaml: Ignoring unrecognized field $.internal-libraries.bar.baz"

      it "warns on missing source-dirs" $ do
        [i|
        name: foo
        internal-libraries:
          bar:
            source-dirs: src
        |] `shouldWarn` pure "Specified source-dir \"src\" does not exist"

    describe "executables" $ do
      it "accepts arbitrary entry points as main" $ do
        touch "src/Foo.hs"
        touch "src/Bar.hs"
        [i|
        executables:
          foo:
            source-dirs: src
            main: Foo
        |] `shouldRenderTo` executable "foo" [i|
        main-is: Foo.hs
        ghc-options: -main-is Foo
        hs-source-dirs:
            src
        other-modules:
            Bar
            Paths_foo
        |]

      context "when inferring modules" $ do
        it "infers other-modules" $ do
          touch "src/Main.hs"
          touch "src/Foo.hs"
          [i|
          executables:
            foo:
              main: Main.hs
              source-dirs: src
          |] `shouldRenderTo` executable "foo" [i|
            main-is: Main.hs
            hs-source-dirs:
                src
            other-modules:
                Foo
                Paths_foo
          |]

        it "allows to specify other-modules" $ do
          touch "src/Foo.hs"
          touch "src/Bar.hs"
          [i|
          executables:
            foo:
              main: Main.hs
              source-dirs: src
              other-modules: Baz
          |] `shouldRenderTo` executable "foo" [i|
            main-is: Main.hs
            hs-source-dirs:
                src
            other-modules:
                Baz
          |]

        it "does not infer any mentioned generated modules" $ do
          touch "src/Foo.hs"
          [i|
          executables:
            foo:
              main: Main.hs
              source-dirs: src
              generated-other-modules: Foo
          |] `shouldRenderTo` (executable "foo" [i|
            main-is: Main.hs
            hs-source-dirs:
                src
            other-modules:
                Paths_foo
                Foo
            autogen-modules:
                Foo
          |]) {packageCabalVersion = ">= 2.0"}

        context "with conditional" $ do
          it "doesn't infer any modules mentioned in that conditional" $ do
            touch "src/Foo.hs"
            touch "src/Bar.hs"
            [i|
            executables:
              foo:
                source-dirs: src
                when:
                  condition: os(windows)
                  other-modules: Foo
            |] `shouldRenderTo` executable "foo" [i|
            other-modules:
                Bar
                Paths_foo
            hs-source-dirs:
                src
            if os(windows)
              other-modules:
                  Foo
            |]

          it "infers other-modules" $ do
            touch "src/Foo.hs"
            touch "windows/Bar.hs"
            [i|
            executables:
              foo:
                source-dirs: src
                when:
                  condition: os(windows)
                  source-dirs: windows
            |] `shouldRenderTo` executable "foo" [i|
            other-modules:
                Foo
                Paths_foo
            hs-source-dirs:
                src
            if os(windows)
              other-modules:
                  Bar
              hs-source-dirs:
                  windows
            |]

      context "with conditional" $ do
        it "does not apply global options" $ do
          -- related bug: https://github.com/sol/hpack/issues/214
          [i|
          ghc-options: -Wall
          executables:
            foo:
              when:
                condition: os(windows)
                main: Foo.hs
          |] `shouldRenderTo` executable_ "foo" [i|
          ghc-options: -Wall
          if os(windows)
            main-is: Foo.hs
          |]

        it "accepts executable-specific fields" $ do
          [i|
          executables:
            foo:
              when:
                condition: os(windows)
                main: Foo
          |] `shouldRenderTo` executable_ "foo" [i|
          if os(windows)
            main-is: Foo.hs
            ghc-options: -main-is Foo
          |]

    describe "when" $ do
      it "accepts conditionals" $ do
        [i|
        when:
          condition: os(windows)
          dependencies: Win32
        executable: {}
        |] `shouldRenderTo` executable_ "foo" [i|
        if os(windows)
          build-depends:
              Win32
        |]
      it "warns on unknown fields" $ do
        [i|
        name: foo
        foo: 23
        when:
          - condition: os(windows)
            bar: 23
            when:
              condition: os(windows)
              bar2: 23
          - condition: os(windows)
            baz: 23
        |] `shouldWarn` [
            "package.yaml: Ignoring unrecognized field $.foo"
          , "package.yaml: Ignoring unrecognized field $.when[0].bar"
          , "package.yaml: Ignoring unrecognized field $.when[0].when.bar2"
          , "package.yaml: Ignoring unrecognized field $.when[1].baz"
          ]

      context "when parsing conditionals with else-branch" $ do
        it "accepts conditionals with else-branch" $ do
          [i|
          when:
            condition: os(windows)
            then:
              dependencies: Win32
            else:
              dependencies: unix
          executable: {}
          |] `shouldRenderTo` executable_ "foo" [i|
          if os(windows)
            build-depends:
                Win32
          else
            build-depends:
                unix
          |]

        it "rejects invalid conditionals" $ do
          [i|
          when:
            condition: os(windows)
            then:
              dependencies: Win32
            else: null
          |] `shouldFailWith` "package.yaml: Error while parsing $.when.else - expected Object, encountered Null"

        it "rejects invalid conditionals" $ do
          [i|
            dependencies:
              - foo
              - 23
          |] `shouldFailWith` "package.yaml: Error while parsing $.dependencies[1] - expected Object or String, encountered Number"

        it "warns on unknown fields" $ do
          [i|
          name: foo
          when:
            condition: os(windows)
            foo: null
            then:
              bar: null
            else:
              when:
                condition: os(windows)
                then: {}
                else:
                  baz: null
          |] `shouldWarn` [
              "package.yaml: Ignoring unrecognized field $.when.foo"
            , "package.yaml: Ignoring unrecognized field $.when.then.bar"
            , "package.yaml: Ignoring unrecognized field $.when.else.when.else.baz"
            ]

    describe "verbatim" $ do
      it "accepts strings" $ do
        [i|
        library:
          verbatim: |
            foo: 23
            bar: 42
        |] `shouldRenderTo` package [i|
        library
          other-modules:
              Paths_foo
          default-language: Haskell2010
          foo: 23
          bar: 42
        |]

      it "accepts multi-line strings as field values" $ do
        [i|
        library:
          verbatim:
            build-depneds: |
              foo
              bar
              baz
        |] `shouldRenderTo` package [i|
        library
          other-modules:
              Paths_foo
          default-language: Haskell2010
          build-depneds:
              foo
              bar
              baz
        |]

      it "allows to null out existing fields" $ do
        [i|
        library:
          verbatim:
            default-language: null
        |] `shouldRenderTo` package [i|
        library
          other-modules:
              Paths_foo
        |]

      context "when specified globally" $ do
        it "overrides header fields" $ do
          [i|
          verbatim:
            cabal-version: ">= 2.0"
          |] `shouldRenderTo` (package "") {packageCabalVersion = ">= 2.0"}

        it "overrides other fields" $ do
          touch "foo"
          [i|
          extra-source-files: foo
          verbatim:
            extra-source-files: bar
          |] `shouldRenderTo` package [i|
          extra-source-files: bar
          |]

        it "is not propagated into sections" $ do
          [i|
          verbatim:
            foo: 23
          library: {}
          |] `shouldRenderTo` package [i|
          library
            other-modules:
                Paths_foo
            default-language: Haskell2010
          foo: 23
          |]

      context "within a section" $ do
        it "overrides section fields" $ do
          [i|
          tests:
            spec:
              verbatim:
                type: detailed-0.9
          |] `shouldRenderTo` package [i|
          test-suite spec
            type: detailed-0.9
            other-modules:
                Paths_foo
            default-language: Haskell2010
          |]

run :: HasCallStack => FilePath -> String -> IO ([String], String)
run c old = run_ c old >>= either assertFailure return

run_ :: FilePath -> String -> IO (Either String ([String], String))
run_ c old = do
  mPackage <- readPackageConfig "" c
  return $ case mPackage of
    Right (pkg, warnings) ->
      let
        FormattingHints{..} = sniffFormattingHints old
        alignment = fromMaybe 0 formattingHintsAlignment
        settings = formattingHintsRenderSettings
        output = Hpack.renderPackage settings alignment formattingHintsFieldOrder formattingHintsSectionsFieldOrder pkg
      in
        Right (warnings, output)
    Left err -> Left err

data RenderResult = RenderResult [String] String
  deriving Eq

instance Show RenderResult where
  show (RenderResult warnings output) = unlines (map ("WARNING in " ++) warnings) ++ output

shouldRenderTo :: HasCallStack => String -> Package -> Expectation
shouldRenderTo input p = do
  writeFile packageConfig ("name: foo\n" ++ unindent input)
  (warnings, output) <- run packageConfig expected
  RenderResult warnings (dropEmptyLines output) `shouldBe` RenderResult [] expected
  where
    expected = dropEmptyLines (renderPackage p)
    dropEmptyLines = unlines . filter (not . null) . lines

shouldWarn :: HasCallStack => String -> [String] -> Expectation
shouldWarn input expected = do
  writeFile packageConfig input
  (warnings, _) <- run packageConfig ""
  sort warnings `shouldBe` sort expected

shouldFailWith :: HasCallStack => String -> String -> Expectation
shouldFailWith input expected = do
  writeFile packageConfig input
  run_ packageConfig "" `shouldReturn` Left expected

customSetup :: String -> Package
customSetup a = (package content) {packageCabalVersion = ">= 1.24", packageBuildType = "Custom"}
  where
    content = [i|
custom-setup
#{indentBy 2 $ unindent a}
|]

library_ :: String -> Package
library_ l = package content
  where
    content = [i|
library
  other-modules:
      Paths_foo
#{indentBy 2 $ unindent l}
  default-language: Haskell2010
|]

library :: String -> Package
library l = package content
  where
    content = [i|
library
#{indentBy 2 $ unindent l}
  default-language: Haskell2010
|]

internalLibrary :: String -> String -> Package
internalLibrary name e = (package content) {packageCabalVersion = ">= 2.0"}
  where
    content = [i|
library #{name}
#{indentBy 2 $ unindent e}
  default-language: Haskell2010
|]

executable_ :: String -> String -> Package
executable_ name e = package content
  where
    content = [i|
executable #{name}
  other-modules:
      Paths_#{name}
#{indentBy 2 $ unindent e}
  default-language: Haskell2010
|]

executable :: String -> String -> Package
executable name e = package content
  where
    content = [i|
executable #{name}
#{indentBy 2 $ unindent e}
  default-language: Haskell2010
|]

package :: String -> Package
package = Package "foo" "0.0.0" "Simple" ">= 1.10"

data Package = Package {
  packageName :: String
, packageVersion :: String
, packageBuildType :: String
, packageCabalVersion :: String
, packageContent :: String
}

renderPackage :: Package -> String
renderPackage Package{..} = unindent [i|
name: #{packageName}
version: #{packageVersion}
build-type: #{packageBuildType}
cabal-version: #{packageCabalVersion}

#{unindent packageContent}
|]

indentBy :: Int -> String -> String
indentBy n = unlines . map (replicate n ' ' ++) . lines
