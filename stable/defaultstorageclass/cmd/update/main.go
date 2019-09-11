package main

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"strings"

	certapi "github.com/jetstack/cert-manager/pkg/api"
	log "github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/apimachinery/pkg/runtime/serializer/json"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/apimachinery/pkg/util/yaml"
	k8scheme "k8s.io/client-go/kubernetes/scheme"
)

const outputDir = "templates"

var objectsFilePath string

var scheme *runtime.Scheme
var decoder runtime.Decoder

func init() {
	scheme = runtime.NewScheme()
	utilruntime.Must(k8scheme.AddToScheme(scheme))
	utilruntime.Must(certapi.AddToScheme(scheme))
	decoder = serializer.NewCodecFactory(scheme).UniversalDeserializer()
}

func main() {
	if len(os.Args) != 2 {
		fmt.Printf("Usage : %s objectsFilePath\n", os.Args[0])
		os.Exit(1)
	}

	objectsFilePath = os.Args[1]

	if err := run(); err != nil {
		log.Error(err, "error in run")
		os.Exit(1)
	}
	log.Infof("Successfully generated helm files from %v", objectsFilePath)
}

const topWarningComment = "# This file is generated from `update.sh`. DO NOT EDIT.\n"

var kindWhitelist = map[string]bool{
	"Certificate":                    true,
	"ClusterRole":                    true,
	"ClusterRoleBinding":             true,
	"Deployment":                     true,
	"Role":                           true,
	"RoleBinding":                    true,
	"Service":                        true,
	"ValidatingWebhookConfiguration": true,
}

var replacements = map[string]string{
	"namespace-to-replace":            "{{ .Release.Namespace }}",
	"dstorageclass-selfsigned-issuer": "{{ .Values.issuer.name }}",
}

func run() error {
	allObjects, err := ReadObjects(objectsFilePath)
	if err != nil {
		return err
	}
	gvkToObjects := map[schema.GroupVersionKind][]runtime.Object{}

	for _, object := range allObjects {
		gvk := object.GetObjectKind().GroupVersionKind()
		gvkToObjects[gvk] = append(gvkToObjects[gvk], object)
	}

	for gvk, objects := range gvkToObjects {
		if !kindWhitelist[gvk.Kind] {
			log.Warnf("skipping Kind not in whitelist: %v", gvk.Kind)
			continue
		}

		yamlString, err := objectsYAMLString(objects)
		if err != nil {
			return nil
		}

		for old, replacement := range replacements {
			yamlString = strings.ReplaceAll(yamlString, old, replacement)
		}

		yamlString = topWarningComment + yamlString

		err = ioutil.WriteFile(path.Join(outputDir, strings.ToLower(gvk.Kind)+".yaml"), []byte(yamlString), 0644)
		if err != nil {
			return nil
		}
	}
	return nil
}

const yamlSeperator = "\n---\n"

func objectsYAMLString(objects []runtime.Object) (string, error) {
	s := json.NewSerializerWithOptions(json.DefaultMetaFactory, scheme, scheme, json.SerializerOptions{
		Yaml:   true,
		Pretty: false,
		Strict: false,
	})

	var objectYAMLs []string
	for _, object := range objects {
		buffer := &bytes.Buffer{}
		if err := s.Encode(object, buffer); err != nil {
			return "", err
		}
		objectYAMLs = append(objectYAMLs, buffer.String())
	}
	return strings.Join(objectYAMLs, yamlSeperator), nil
}

func ReadObjects(filename string) ([]runtime.Object, error) {
	data, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	var objects []runtime.Object

	for _, objYaml := range strings.Split(string(data), "---") {
		jsonBytes, err := yaml.ToJSON([]byte(objYaml))
		if err != nil {
			return nil, err
		}

		object, _, err := decoder.Decode(jsonBytes, nil, nil)
		if err != nil {
			return nil, err
		}

		objects = append(objects, object)
	}
	return objects, nil
}
