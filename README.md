# docker-mock-rpmbuilder

Build RPMs using the Mock Project (for any platform).  This git fork extends
https://github.com/mmornati/docker-mock-rpmbuilder to ensure the output
is not owned by root using the `OWNERSHIP` environment variable.


## Usage

```bash
# Build the docker image
docker build -t mock-rpmbuilder:latest .


# Prepare the RPM
MOCK_CONFIG=rocky-8-x86_64
SOURCE=/path/to/package.src.tar.gz
SPECFILE=/path/to/package.spec

mkdir -p rpmbuild/SOURCE rpmbuild/SPECS
cp ${SOURCE} rpmbuild/SOURCE/.
cp ${SPEC} rpmbuild/SPECS/.

# Build your RPM
docker run --rm --privileged=true \
     --volume="$(CWD)/rpmbuild:/rpmbuild" \
     -e MOUNT_POINT="/rpmbuild" \
     -e OWNERSHIP="$(id -u):$(id -g)" \
     -e MOCK_CONFIG="${MOCK_CONFIG}" \
     -e SOURCES="SOURCES/$(basename ${SOURCE})" \
     -e SPEC_FILE="SPECS/$(basename ${SPECFILE})" \
     -e NETWORK=true \
     mock-rpmbuilder:latest
```

The RPM build output will be found in `rpmbuild/output`

Consult https://github.com/mmornati/docker-mock-rpmbuilder for further details.
