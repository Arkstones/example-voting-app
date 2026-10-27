# The .NET SDK does not run under QEMU emulation, so we always build on the
# builder's own platform and cross-compile for the target (-a $TARGETARCH).
# To build for ARM on an Intel machine:
#   docker buildx build --platform linux/arm64 .

# build: compile the worker with the .NET 10 SDK (LTS)
FROM --platform=${BUILDPLATFORM} mcr.microsoft.com/dotnet/sdk:10.0@sha256:de4fe90a98845d75910b9769662465c84de1a934665c431279d1382b2bddc02b AS build
ARG TARGETARCH
WORKDIR /source

# restore packages first so this layer is cached between code changes
COPY *.csproj .
RUN dotnet restore -a $TARGETARCH

COPY . .
RUN dotnet publish -c Release -o /app -a $TARGETARCH --self-contained false --no-restore

# final: only the small .NET runtime and the compiled app
FROM mcr.microsoft.com/dotnet/runtime:10.0@sha256:a3f9f81954b9c810af2ed18849716c8dc74a4707bd0907fdbd69be81554c0f30
WORKDIR /app
COPY --from=build /app .

# the .NET images come with a non-root "app" user; APP_UID is its numeric id (1654),
# numeric so Kubernetes can verify runAsNonRoot
USER $APP_UID

ENTRYPOINT ["dotnet", "Worker.dll"]
