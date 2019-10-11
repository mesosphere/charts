package main

import (
	"bytes"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"strings"

	certapi "github.com/jetstack/cert-manager/pkg/api"
	"github.com/jetstack/cert-manager/pkg/apis/certmanager/v1alpha1"
	log "github.com/sirupsen/logrus"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/apimachinery/pkg/runtime/serializer/json"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/apimachinery/pkg/util/yaml"
	k8scheme "k8s.io/client-go/kubernetes/scheme"
)

const outputDir = "templates"

var (
	scheme         *runtime.Scheme
	decoder        runtime.Decoder
	yamlSerializer *json.Serializer
)

func defaultSerialize(object runtime.Object) (string, error) {
	buffer := &bytes.Buffer{}
	if err := yamlSerializer.Encode(object, buffer); err != nil {
		return "", err
	}
	return buffer.String(), nil
}

func init() {
	scheme = runtime.NewScheme()
	utilruntime.Must(k8scheme.AddToScheme(scheme))
	utilruntime.Must(certapi.AddToScheme(scheme))
	decoder = serializer.NewCodecFactory(scheme).UniversalDeserializer()

	yamlSerializer = json.NewSerializerWithOptions(json.DefaultMetaFactory, scheme, scheme, json.SerializerOptions{
		Yaml:   true,
		Pretty: false,
		Strict: false,
	})
}

func main() {
	if len(os.Args) != 2 {
		fmt.Printf("Usage : %s objectsFilePath\n", os.Args[0])
		os.Exit(1)
	}

	objectsFilePath := os.Args[1]

	if err := run(objectsFilePath); err != nil {
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

var kindToCustomSerializer = map[string]func(object runtime.Object) (string, error){
	"Certificate": func(object runtime.Object) (string, error) {
		certificate, ok := object.(*v1alpha1.Certificate)
		if !ok {
			return "", fmt.Errorf("failed to convert runtime.Object to Certificate")
		}
		certificate.Spec.IssuerRef.Kind = "{{ .Values.issuer.kind }}"
		return defaultSerialize(certificate)
	},
	"Deployment": func(object runtime.Object) (string, error) {
		deployment, ok := object.(*appsv1.Deployment)
		if !ok {
			return "", fmt.Errorf("failed to convert runtime.Object to Deployment")
		}

		// set temp values for resource requires and replace values after
		tempValuesToReplacement := map[string]string{}
		setTempValue := func(container *corev1.Container, key string) {
			resourceValue := fmt.Sprintf("%vm", len(tempValuesToReplacement)+1)

			container.Resources = corev1.ResourceRequirements{
				Limits: corev1.ResourceList{
					"replace-me": resource.MustParse(resourceValue),
				},
			}
			s := "\n          "
			replaceKey := fmt.Sprintf("resources:%slimits:%s  replace-me: %s", s, s, resourceValue)
			helmTemplate := []string{
				fmt.Sprintf("{{ with .Values.%s.resources }}", key),
				"{{- toYaml . | nindent 12 }}",
				"{{- end }}",
			}
			tempValuesToReplacement[replaceKey] = fmt.Sprintf("resources:%s%s", s, strings.Join(helmTemplate, s))
		}

		var containersCopy []corev1.Container
		for _, container := range deployment.Spec.Template.Spec.Containers {
			switch container.Name {
			case "kube-rbac-proxy":
				setTempValue(&container, "kubeRbacProxy")
			case "manager":
				setTempValue(&container, "manager")
			default:
				return "", fmt.Errorf("did not handle container resource")
			}

			containersCopy = append(containersCopy, container)
		}
		deployment.Spec.Template.Spec.Containers = containersCopy

		objString, err := defaultSerialize(deployment)
		if err != nil {
			return "", err
		}

		for old, replacement := range tempValuesToReplacement {
			found := strings.Count(objString, old)
			if found != 1 {
				return "", fmt.Errorf("found %v `%s` in `%s` instead of 1", found, old, objString)
			}
			objString = strings.Replace(objString, old, replacement, 1)
		}
		return objString, nil
	},
}

var replacements = map[string]string{
	"namespace-to-replace":             "{{ .Release.Namespace }}",
	"prefix-replace-selfsigned-issuer": "{{ .Values.issuer.name }}",

	// DO PREFIX REPLACEMNTS LAST
	// this prefix is short because some names end up getting big and there should only be 1 instance of this chart
	"prefix-replace-":     "dstorageclass-",
	"webhook-server-cert": "dstorageclass-webhook-server-cert",
}

func run(objectsFilePath string) error {
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
			return err
		}

		for old, replacement := range replacements {
			yamlString = strings.ReplaceAll(yamlString, old, replacement)
		}

		yamlString = topWarningComment + yamlString

		err = ioutil.WriteFile(path.Join(outputDir, strings.ToLower(gvk.Kind)+".yaml"), []byte(yamlString), 0644)
		if err != nil {
			return err
		}
	}
	return nil
}

const yamlSeparator = "\n---\n"

func objectsYAMLString(objects []runtime.Object) (string, error) {
	var objectYAMLs []string
	for _, object := range objects {
		kind := object.GetObjectKind().GroupVersionKind().Kind
		customSerializer, hasCustomSerializer := kindToCustomSerializer[kind]
		if hasCustomSerializer {
			yaml, err := customSerializer(object)
			if err != nil {
				return "", fmt.Errorf("error with custom serializer for kind %s: %w", kind, err)
			}
			if yaml != "" {
				objectYAMLs = append(objectYAMLs, yaml)
				continue
			}
		}

		objString, err := defaultSerialize(object)
		if err != nil {
			return "", err
		}
		objectYAMLs = append(objectYAMLs, objString)
	}
	return strings.Join(objectYAMLs, yamlSeparator), nil
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
