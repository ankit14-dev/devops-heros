# Stage 1: compile with the full JDK
FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /src
COPY HelloWorld.java .
RUN javac HelloWorld.java

# Stage 2: run with the smaller JRE only
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /src/*.class ./
EXPOSE 8080
CMD ["java", "HelloWorld"]
