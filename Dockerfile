# Use Ubuntu as the base image
FROM ubuntu:22.04

# Avoid timezone prompt during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

# Install necessary packages
RUN apt-get update && apt-get install -y \
    curl \
    git \
    default-jdk \
    unzip \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Coursier
RUN curl -fL "https://github.com/coursier/launchers/raw/master/cs-x86_64-pc-linux.gz" | gzip -d > cs && \
    chmod +x cs && \
    ./cs setup -y && \
    mv cs /usr/local/bin/

# Install SBT
RUN curl -L -o sbt-1.9.8.deb https://repo.scala-sbt.org/scalasbt/debian/sbt-1.9.8.deb && \
    dpkg -i sbt-1.9.8.deb && \
    rm sbt-1.9.8.deb

# Set environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=$PATH:$JAVA_HOME/bin:/root/.local/share/coursier/bin

# Create workspace directory
WORKDIR /workspace

# Create project directory structure
RUN mkdir -p /workspace/pekko-sample/src/main/scala/com/example

# Add build.sbt with Pekko dependencies
COPY <<EOF /workspace/pekko-sample/build.sbt
ThisBuild / version := "0.1.0-SNAPSHOT"
ThisBuild / scalaVersion := "2.13.12"

lazy val root = (project in file("."))
  .settings(
    name := "pekko-sample",
    libraryDependencies ++= Seq(
      "org.apache.pekko" %% "pekko-actor-typed" % "1.0.2",
      "org.apache.pekko" %% "pekko-stream" % "1.0.2",
      "org.apache.pekko" %% "pekko-http" % "1.0.0",
      "ch.qos.logback" % "logback-classic" % "1.4.14"
    )
  )
EOF

# Add sample Pekko code
COPY <<EOF /workspace/pekko-sample/src/main/scala/com/example/SamplePekko.scala
package com.example

import org.apache.pekko.actor.typed.{ActorSystem, Behavior, ActorRef}
import org.apache.pekko.actor.typed.scaladsl.Behaviors
import scala.concurrent.duration._
import scala.concurrent.Await

sealed trait Message
case class Ping(count: Int, replyTo: ActorRef[Message]) extends Message
case class Pong(count: Int, replyTo: ActorRef[Message]) extends Message

object Actor1 {
  def apply(): Behavior[Message] = Behaviors.receive { (context, message) =>
    message match {
      case Pong(count, replyTo) =>
        context.log.info(s"Actor1 received Pong: $count")
        if (count < 5) {
          replyTo ! Ping(count + 1, context.self)
        } else {
          context.log.info("Ping-Pong completed!")
          context.system.terminate()
        }
        Behaviors.same
      case _ => Behaviors.same
    }
  }
}

object Actor2 {
  def apply(): Behavior[Message] = Behaviors.receive { (context, message) =>
    message match {
      case Ping(count, replyTo) =>
        context.log.info(s"Actor2 received Ping: $count")
        replyTo ! Pong(count, context.self)
        Behaviors.same
      case _ => Behaviors.same
    }
  }
}

object Main {
  def main(args: Array[String]): Unit = {
    val system = ActorSystem(Behaviors.setup[Message] { context =>
      val actor1 = context.spawn(Actor1(), "actor1")
      val actor2 = context.spawn(Actor2(), "actor2")
      actor2 ! Ping(1, actor1)
      Behaviors.empty
    }, "PingPongSystem")

    Await.result(system.whenTerminated, 1.minute)
  }
}
EOF

# Add logback configuration
COPY <<EOF /workspace/pekko-sample/src/main/resources/logback.xml
<configuration>
    <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <root level="INFO">
        <appender-ref ref="STDOUT" />
    </root>
</configuration>
EOF

# Set the working directory to the project
WORKDIR /workspace/pekko-sample

# Initial compilation
RUN sbt compile

# Command to keep container running
CMD ["tail", "-f", "/dev/null"]
