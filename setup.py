import sys
import os
import shutil
from setuptools import setup, find_packages
import configparser
from pathlib import Path
from Cython.Build import cythonize
from Cython.Build.Dependencies import default_create_extension

PROJECT_PATH = Path(__file__).parent
BUILD_CONF_FN = PROJECT_PATH.joinpath('build.conf')
WIN32 = sys.platform == 'win32'
IS_BUILD = len({'sdist', 'bdist_wheel', 'build_ext'} & set(sys.argv)) > 0

try:
    import numpy
except ImportError:
    numpy = None


def get_local_config():
    if not BUILD_CONF_FN.exists():
        return {}
    # d = {'portaudio':{}}
    conf = configparser.ConfigParser()
    conf.read_dict({
        'setuptools-data':{
            'data_path':'_cysounddevice_data',
        },
        'portaudio':{'dll_path':'None', 'src_path':'None'},
    })
    conf.read(BUILD_CONF_FN)
    # sources = conf['portaudio']
    # d['portaudio']['dll_path'] = conf.get('portaudio', 'dll_path', '')
    # d['portaudio']['src'] = conf.get('portaudio', 'src_path', '')
    return conf

def copy_file(src_file, dest_file):
    assert src_file.is_file()
    src_st = src_file.stat()
    if dest_file.exists():
        assert dest_file.is_file()
        changed = False
        dest_st = dest_file.stat()
        if src_st.st_size != dest_st.st_size:
            changed = True
        elif src_st.st_ctime > dest_st.st_ctime:
            changed = True
        if not changed:
            return False
    # dest_file.write_bytes(src_file.read_bytes())
    # dest_file.chmod(src_st.st_mode)
    print(f'{src_file}  ->  {dest_file}')
    shutil.copy2(str(src_file.resolve()), str(dest_file.resolve()))
    return True

def build_config():
    conf = get_local_config()
    # data_path = base_p.joinpath(conf['setuptools-data']['data_path'])
    data_path = PROJECT_PATH.joinpath('_cysounddevice_data')
    dll_dest = data_path.joinpath('lib')
    incl_dest = data_path.joinpath('include')
    dll_dest.mkdir(parents=True, exist_ok=True)
    incl_dest.mkdir(parents=True, exist_ok=True)

    dll_src = Path(conf['portaudio']['dll_path']).expanduser()
    assert dll_src.exists()
    assert dll_src.is_dir()
    incl_src = Path(conf['portaudio']['src_path']).expanduser()
    assert incl_src.exists()
    assert incl_src.exists()

    for pattern in ['*.dll', '*.lib', '*.exp']:
        for src_file in dll_src.glob(pattern):
            dest_file = dll_dest.joinpath(src_file.name)
            copy_file(src_file, dest_file)
    for src_file in incl_src.glob('*.h'):
        dest_file = incl_dest.joinpath(src_file.name)
        copy_file(src_file, dest_file)
    initpy = data_path.joinpath('__init__.py')
    if not initpy.exists():
        initpy.write_text('')
    conf_dict = {
        'data_path':data_path,
        'dll_dest':dll_dest,
        'incl_dest':incl_dest,
        'conf':conf,
        'packages':[data_path.name],
        'package_data':{
            data_path.name:['include/*', 'lib/*'],
        },
    }
    print(conf_dict)
    return conf_dict

if WIN32 and IS_BUILD:
    BUILD_CONF = build_config()
else:
    BUILD_CONF = None

if numpy is None:
    NP_INC = None
else:
    # INCLUDE_PATH = [NP_INC]
    NP_INC = numpy.get_include()

def my_create_extension(template, kwds):
    # libs = kwds.get('libraries', []) + ["mylib"]
    # kwds['libraries'] = libs
    include_dirs = kwds.get('include_dirs', [])
    if BUILD_CONF:
        include_dirs.append(str(BUILD_CONF['incl_dest'].resolve()))
    # include_dirs.append(PA_INC)
    if NP_INC and NP_INC not in include_dirs:
        include_dirs.append(NP_INC)
    kwds['include_dirs'] = include_dirs

    library_dirs = kwds.get('library_dirs', [])
    if BUILD_CONF:
        library_dirs.append(str(BUILD_CONF['dll_dest'].resolve()))
    kwds['library_dirs'] = library_dirs
    return default_create_extension(template, kwds)

ext_modules = cythonize(
    ['cysounddevice/**/*.pyx'],
    # include_path=INCLUDE_PATH,
    annotate=True,
    # gdb_debug=True,
    compiler_directives={
        'linetrace':True,
        'embedsignature':True,
    },
    create_extension=my_create_extension,
)

PACKAGE_DATA = {
    '*':['README.md'],
    'cysounddevice':['*.pxd'],
}
PACKAGES = ['cysounddevice']
if BUILD_CONF:
    PACKAGES.extend(BUILD_CONF['packages'])
    PACKAGE_DATA.update(BUILD_CONF['package_data'])

setup(
    packages=PACKAGES,
    ext_modules=ext_modules,
    include_package_data=True,
    package_data=PACKAGE_DATA,
)
