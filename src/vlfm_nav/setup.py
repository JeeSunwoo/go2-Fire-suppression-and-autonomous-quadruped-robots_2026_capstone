from setuptools import setup

package_name = 'vlfm_nav'

setup(
    name=package_name,
    version='0.0.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='unitree',
    maintainer_email='unitree@todo.todo',
    description='VLFM 빛 발원지 탐색 VLM 노드 (vlfm_source_nav_v20)',
    license='TODO: License declaration',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'vlfm_source_nav = vlfm_nav.vlfm_source_nav_v20:main',
        ],
    },
)
