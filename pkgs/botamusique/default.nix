{
  stdenv,
  lib,
  python3Packages,
  fetchFromGitHub,
}:
  python3Packages.buildPythonApplication rec {
    pname = "propagandabot";
    version = "v6.5-0";
    src = fetchFromGitHub {
      owner = "ult1m4";
      repo = "PropagandaBot";
      rev = "4255d5c6e8d9822bcb37b27af45e5e4ee9639494";
      sha256 = "XaS9rjDnPpYjBJX0jCiqr588JMyLA+S+ul+3fiyNhHA=";
    };
    vendorHash = "sha256-QcGAnfjcka5JxLm/3NAeswAPohCNEUrWCLvajs2lLyw=";

    dependencies = with python3Packages; [
      pymumble
      yt-dlp
      packaging
      mutagen
      python-magic
      pillow
      pyradios
      flask
    ];

    build-system = with python3Packages; [
      setuptools
    ];

    preBuild = ''
      ls -al
      cat > launcher.py << 'EOF'
      import runpy
      import os

      def main():
        here = os.path.dirname(__file__)
        path = os.path.join(here, 'mumbleBot.py')
        runpy.run_path(path, run_name='__main__')
      EOF

      cat > setup.py << EOF
      from setuptools import setup, find_packages

      with open('requirements.txt') as f:
          install_requires = f.read().splitlines()

      setup(
        name='${pname}',
        #packages=['someprogram'],
        version='${version}',
        #author='...',
        packages=find_packages(),
        py_modules=['mumbleBot', 'variables', 'database', 'util', 'interface', 'command', 'constants', 'launcher'],
        #description='...',
        install_requires=install_requires,
        entry_points={
          'console_scripts': [
            'mumbleBot=launcher:main',
          ],
        },
      )
      EOF
    '';
    
    meta = {
      description = "Fork of Botamusique to support YT-DLP and modern stream functionality. Intended to be static, with manual updates to YT-DLP.";
      license = lib.licenses.mit;
      homepage = "https://github.com/${src.owner}/${src.repo}";
    };
  }
