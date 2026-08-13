# Build a Flink 1.18 image with the event-counter JAR baked in at /opt/flink/usrlib/.
# Application-mode Flink (which FlinkDeployment.spec.job uses) only supports
# local:// JAR URIs -- the JAR must be present INSIDE the container image.
# HTTP jarURI + ConfigMap mounts do not work in application mode.
#
# Usage:
#   cd flink-job/src/
#   mvn package                                     # produces target/event-counter.jar
#   cp target/event-counter.jar .
#   docker build -t event-counter:local .
#   kind load docker-image event-counter:local --name flink-lab
#
# The FlinkDeployment CR then references image: event-counter:local and
# jarURI: local:///opt/flink/usrlib/event-counter.jar.

FROM flink:1.18
COPY event-counter.jar /opt/flink/usrlib/event-counter.jar
