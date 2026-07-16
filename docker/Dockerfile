FROM opendronemap/odm as build

RUN pip3 install awscli
RUN apt-get update && apt-get install -y libimage-exiftool-perl && rm -rf /var/lib/apt/lists/*

COPY --chmod=777 entry.sh /

# Override the default ENTRYPOINT from the ODM image
ENTRYPOINT [ "/entry.sh" ]
